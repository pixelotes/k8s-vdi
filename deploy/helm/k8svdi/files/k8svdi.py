# k8svdi hub configuration, loaded by Z2JH from jupyterhub_config.d.
# Settings come from /etc/k8svdi/config.json (chart values); the OIDC client
# secret from /etc/k8svdi/oidc/client-secret.
import datetime
import json
import logging
from urllib.parse import quote

cfg = json.load(open("/etc/k8svdi/config.json"))
auth = cfg["auth"]
base_url = f"https://{cfg['host']}"
client_secret = open("/etc/k8svdi/oidc/client-secret").read().strip()

# --- Authentication -----------------------------------------------------------
if auth["provider"] == "entra":
    # Microsoft Entra ID. Authorization values come from App Roles ("roles") by default.
    entra = auth["entra"]
    c.JupyterHub.authenticator_class = "azuread"
    c.AzureAdOAuthenticator.tenant_id = entra["tenantId"]
    # v2.0 endpoints: id_token carries preferred_username and roles.
    login = f"https://login.microsoftonline.com/{entra['tenantId']}/oauth2/v2.0"
    c.AzureAdOAuthenticator.authorize_url = f"{login}/authorize"
    c.AzureAdOAuthenticator.token_url = f"{login}/token"
    c.AzureAdOAuthenticator.username_claim = "preferred_username"
    c.AzureAdOAuthenticator.auth_state_groups_key = f"user.{entra['groupsClaim']}"
    c.AzureAdOAuthenticator.scope = ["openid", "profile", "email"]
    c.AzureAdOAuthenticator.login_service = "Microsoft"
    c.AzureAdOAuthenticator.logout_redirect_url = (
        f"https://login.microsoftonline.com/{entra['tenantId']}/oauth2/v2.0/logout"
        f"?post_logout_redirect_uri={quote(base_url + '/', safe='')}")
    authenticator = c.AzureAdOAuthenticator
else:
    # Keycloak (directly, or brokering Entra/other IdPs behind it).
    kc = auth["keycloak"]
    public = kc["realmUrl"].rstrip("/")
    internal = (kc.get("internalRealmUrl") or public).rstrip("/")
    c.JupyterHub.authenticator_class = "generic-oauth"
    c.GenericOAuthenticator.authorize_url = f"{public}/protocol/openid-connect/auth"
    c.GenericOAuthenticator.token_url = f"{internal}/protocol/openid-connect/token"
    c.GenericOAuthenticator.userdata_url = f"{internal}/protocol/openid-connect/userinfo"
    c.GenericOAuthenticator.username_claim = "preferred_username"
    c.GenericOAuthenticator.auth_state_groups_key = "oauth_user.groups"
    c.GenericOAuthenticator.scope = ["openid", "profile", "email"]
    c.GenericOAuthenticator.login_service = "Keycloak"
    if kc.get("logoutRedirect", True):
        c.GenericOAuthenticator.logout_redirect_url = (
            f"{public}/protocol/openid-connect/logout?client_id={auth['clientId']}"
            f"&post_logout_redirect_uri={quote(base_url + '/', safe='')}")
    authenticator = c.GenericOAuthenticator

authenticator.client_id = auth["clientId"]
authenticator.client_secret = client_secret
authenticator.oauth_callback_url = f"{base_url}/hub/oauth_callback"
authenticator.allowed_groups = set(auth["allowedGroups"])
authenticator.admin_groups = set(auth["adminGroups"])
authenticator.manage_groups = True
c.Authenticator.auto_login = True

# --- Profiles per group/role ---------------------------------------------------
PROFILES = cfg.get("profiles") or []


def profile_list(spawner):
    groups = {g.name for g in spawner.user.groups}
    return [
        {"slug": p["slug"], "display_name": p["displayName"],
         "description": p.get("description", ""), "default": p.get("default", False),
         "kubespawner_override": p.get("override", {})}
        for p in PROFILES if groups & set(p.get("groups", []))
    ]


def options_form(spawner):
    # Only ask when there is a real choice; a single profile is applied silently.
    profiles = profile_list(spawner)
    return spawner._render_options_form(profiles) if len(profiles) > 1 else ""


if PROFILES:
    c.KubeSpawner.profile_list = profile_list
    c.KubeSpawner.options_form = options_form

# --- Audit trail ---------------------------------------------------------------
if cfg.get("audit", {}).get("enabled", True):
    _audit_log = logging.getLogger("k8svdi.audit")

    def audit(event, user, **fields):
        rec = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
               "event": event, "user": user, **fields}
        line = json.dumps(rec, ensure_ascii=False)
        _audit_log.warning("AUDIT %s", line)
        try:
            with open("/srv/jupyterhub/audit.jsonl", "a") as f:
                f.write(line + "\n")
        except OSError:
            pass  # no hub PVC: stdout only

    async def post_auth_hook(authenticator, handler, auth_model):
        if auth_model:
            audit("login", auth_model["name"],
                  ip=handler.request.remote_ip, groups=auth_model.get("groups"))
        return auth_model

    def pre_spawn_hook(spawner):
        # Profile overrides are applied later in start(); report the profile's own values.
        slug = (spawner.user_options or {}).get("profile")
        prof = next((p for p in PROFILES if p["slug"] == slug),
                    next((p for p in PROFILES if p.get("default")), {}))
        override = prof.get("override", {})
        audit("desktop_start", spawner.user.name, profile=prof.get("slug"),
              cpu=override.get("cpu_limit"), mem=override.get("mem_limit"))

    def post_stop_hook(spawner):
        audit("desktop_stop", spawner.user.name)

    c.Authenticator.post_auth_hook = post_auth_hook
    c.Spawner.pre_spawn_hook = pre_spawn_hook
    c.Spawner.post_stop_hook = post_stop_hook
else:
    def audit(*args, **kwargs):
        pass

# --- Logout --------------------------------------------------------------------
from jupyterhub.handlers.login import LogoutHandler

_orig_logout = LogoutHandler.get


async def _logout(self):
    user = self.current_user
    if user:
        audit("logout", user.name, ip=self.request.remote_ip)
        # shutdown_on_logout skips desktops still starting; wait so they get stopped too.
        for spawner in user.spawners.values():
            if spawner.pending == "spawn" and spawner._spawn_future:
                try:
                    await spawner._spawn_future
                except Exception:
                    pass
    return await _orig_logout(self)


LogoutHandler.get = _logout
