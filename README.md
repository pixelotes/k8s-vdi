# k8svdi

Escritorios Linux en el navegador sobre **kind + OrbStack**. Cada usuario hace login con **Keycloak** y obtiene su propio pod con XFCE + noVNC, que se destruye al hacer logout o apagar.

## Requisitos

- macOS con [OrbStack](https://orbstack.dev) arrancado.
- `kubectl`, `docker`. `kind` y `helm` se instalan con Homebrew si faltan.

## Uso

```bash
./scripts/up.sh       # levanta todo (idempotente): cluster, ingress, gateway, Keycloak, portal
./scripts/info.sh     # URLs y credenciales
./scripts/e2e-test.sh # test end-to-end: login -> pod -> escritorio -> logout/apagar -> pod borrado
./scripts/audit.sh    # auditoría: login, logout, desktop_start, desktop_stop
./scripts/down.sh     # destruye el cluster (conserva .secrets/)
```

Abre **https://vdi.orb.local** y entra con un usuario de `./scripts/info.sh`.

## Arquitectura

```
Navegador ─https─► OrbStack (TLS, CA de confianza en el Mac)
                    └─ vdi-gw (socat, *.vdi.orb.local) ─► ingress-nginx (nodo kind)
                         ├─ keycloak.vdi.orb.local → Keycloak (realm "vdi")
                         └─ vdi.orb.local          → JupyterHub ─ KubeSpawner ─► pod jupyter-<user>
                                                                                 XFCE + TigerVNC + noVNC
                                                                                 /home en PVC claim-<user>
```

| Componente | Detalle |
|---|---|
| Gateway | OrbStack enruta HTTPS al puerto expuesto del contenedor y los nodos kind no admiten labels: el contenedor `vdi-gw` posee el dominio `*.vdi.orb.local` y reenvía al ingress. |
| Keycloak | Modo dev; el realm se reimporta en cada arranque desde `keycloak/realm-vdi.json.tpl` + `keycloak/users.txt`. Cliente OIDC `jupyterhub` con claim `groups`. |
| Backchannel | El Hub habla con Keycloak por `http://keycloak.keycloak.svc:8080` (los pods no confían en la CA de OrbStack); el issuer sigue siendo la URL pública https. |
| Portal | Chart `deploy/helm/k8svdi` (JupyterHub 4.4.3) con auto-login, `shutdown_on_logout` y Keycloak o Entra. |
| Escritorio | `images/desktop`: base-notebook + XFCE + TigerVNC + `jupyter-remote-desktop-proxy` + Epiphany (navegador ligero). |

## Chart de Helm y Argo CD

`deploy/helm/k8svdi` es un chart paraguas sobre el chart oficial de JupyterHub (4.4.3). El laboratorio lo usa (`scripts/30-portal.sh`) y sirve igual para producción.

| Valor | Uso |
|---|---|
| `host` | Hostname público del portal |
| `auth.provider` | `keycloak` o `entra` |
| `auth.clientId`, `auth.clientSecret` | Cliente OIDC. Sin `clientSecret`, el chart espera un Secret `k8svdi-oidc` (clave `client-secret`) creado fuera (External Secrets, Sealed Secrets...) |
| `auth.allowedGroups`, `auth.adminGroups` | Grupos de Keycloak o App Roles de Entra |
| `auth.keycloak.realmUrl`, `internalRealmUrl` | URL pública del realm y, opcional, URL interna para el backchannel |
| `auth.entra.tenantId`, `groupsClaim` | Tenant y claim de autorización (`roles` recomendado) |
| `profiles` | Perfiles de escritorio por grupo/rol |
| `audit.enabled` | Auditoría |
| `jupyterhub.*` | Se pasa tal cual al chart de JupyterHub (ingress, TLS, imagen, storage, culler...) |

Ficheros de valores en `deploy/values/`:

- `lab-keycloak.yaml`: este laboratorio.
- `prod-entra.example.yaml`: Entra directo. App Registration con redirect `https://<host>/hub/oauth_callback` y App Roles `vdi-users` / `vdi-admins`.
- `prod-keycloak.example.yaml`: Keycloak. Para que Keycloak delegue el login en Entra, fusiona `keycloak/entra-broker.example.json` en el realm; los App Roles de Entra se mapean a grupos y el portal no cambia.

```bash
helm dependency build deploy/helm/k8svdi
helm upgrade --install vdi deploy/helm/k8svdi -n vdi --create-namespace -f deploy/values/prod-entra.yaml
```

Argo CD: `deploy/argocd/k8svdi-entra.yaml` y `k8svdi-keycloak.yaml` (ajusta `repoURL` y copia el `.example.yaml` correspondiente). La configuración de k8svdi solo se lee al arrancar el Hub; un hook post-upgrade (PostSync en Argo) lo reinicia en cada actualización sin afectar a los escritorios abiertos.

## Ciclo de vida del escritorio

El pod `jupyter-<user>` se borra cuando:

- el usuario hace logout del portal (también si el escritorio aún estaba arrancando);
- cierra sesión en XFCE (`vdi-xstartup`);
- usa el lanzador **Apagar escritorio** (`vdi-shutdown`, llama a la API del Hub);
- lleva 30 min inactivo (idle culler).

El `/home/jovyan` persiste en el PVC `claim-<user>` (2 Gi). Para resetear a un usuario: `kubectl --context kind-vdi -n vdi delete pvc claim-<user>`.

## Perfiles por grupo

| Grupo Keycloak | Perfiles |
|---|---|
| `vdi-users` | Estándar (1 CPU / 2 GB), sin formulario |
| `vdi-admins` | Estándar o Potente (2 CPU / 4 GB); además admin del Hub (`/hub/admin`) |

Se definen en `profiles` de los valores del chart.

## Usuarios y secretos

- Usuarios en `keycloak/users.txt` (`usuario nombre apellido grupos`). Tras editarlo: `./scripts/20-keycloak.sh`.
- Las contraseñas se generan en el primer arranque en `.secrets/` (ignorado por git) y se reutilizan. Borra un fichero para rotarla.

## Hooks y auditoría

`deploy/helm/k8svdi/files/k8svdi.py` define `post_auth_hook`, `pre_spawn_hook`, `post_stop_hook` y un wrapper del logout. Cada evento se escribe como JSON en el log del Hub (`AUDIT ...`) y en `/srv/jupyterhub/audit.jsonl` (PVC del Hub).

## Capacidad orientativa

Un escritorio en reposo usa ~235 MB; con navegador, ~1–1,5 GB. En un nodo de 64 GB caben unos 40–50 escritorios de uso típico. Para reflejarlo en el scheduler, sube `singleuser.memory.guarantee` a ~1 G.

## Limitaciones conocidas

- ingress-nginx dejó de mantenerse en marzo de 2026; candidato a sustituir por Traefik o Gateway API.
- `NetworkPolicy` de los escritorios activadas (egress a IPs privadas bloqueado salvo el Hub).
- Keycloak en modo dev sin base de datos persistente: los cambios hechos a mano en la consola se pierden al reiniciar.
- El logout de Keycloak muestra una pantalla de confirmación (no se envía `id_token_hint`).
- WebKit corre sin su sandbox (`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`); el aislamiento es el propio pod.
