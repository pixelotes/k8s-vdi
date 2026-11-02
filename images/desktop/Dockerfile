FROM quay.io/jupyter/base-notebook:2026-10-12

USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      dbus-x11 xfce4 xfce4-terminal xfce4-panel xfce4-session xfce4-settings \
      tigervnc-standalone-server tigervnc-tools xorg xauth \
      epiphany-browser mousepad ristretto thunar-archive-plugin fonts-dejavu \
      locales sudo curl ca-certificates \
    && apt-get remove -y xfce4-screensaver light-locker 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/*

# Session lifecycle: when the XFCE session ends (logout) or the user clicks
# "Apagar", the single-user server stops and the Hub deletes the pod.
COPY vdi-xstartup /usr/local/bin/vdi-xstartup
COPY vdi-shutdown /usr/local/bin/vdi-shutdown
COPY apagar.desktop /usr/share/applications/apagar.desktop
# Epiphany (GNOME Web) as the lightweight default browser. WebKit's bubblewrap
# sandbox can't run in an unprivileged pod; the pod itself is the sandbox.
COPY helpers.rc /etc/xdg/xfce4/helpers.rc
ENV WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
RUN chmod 755 /usr/local/bin/vdi-xstartup /usr/local/bin/vdi-shutdown

ENV JUPYTER_REMOTE_DESKTOP_PROXY_XSTARTUP=/usr/local/bin/vdi-xstartup
USER ${NB_USER}
# Hub/single-user versions must match the jupyterhub chart (4.4.3 -> JupyterHub 5.5.3).
RUN pip install --no-cache-dir 'jupyterhub==5.5.3' 'jupyter-remote-desktop-proxy==3.*'

