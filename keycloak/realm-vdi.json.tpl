{
  "realm": "vdi",
  "enabled": true,
  "displayName": "K8s VDI",
  "loginWithEmailAllowed": true,
  "groups": [{"name": "vdi-users"}, {"name": "vdi-admins"}],
  "clients": [
    {
      "clientId": "jupyterhub",
      "name": "VDI portal",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${JUPYTERHUB_CLIENT_SECRET}",
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": false,
      "redirectUris": ["https://vdi.orb.local/hub/oauth_callback"],
      "webOrigins": ["https://vdi.orb.local"],
      "attributes": {"post.logout.redirect.uris": "https://vdi.orb.local/*"},
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "config": {"claim.name": "groups", "full.path": "false",
                     "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true"}
        }
      ]
    }
  ],
  "users": [
${USERS_JSON}
  ]
}
