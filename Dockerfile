FROM phusion/baseimage:noble-1.0.2

# Install dependencies for nvm and extra tools
RUN apt-get update && apt-get install -y \
    curl build-essential ca-certificates \
    vim git less locales jq iproute2 byobu && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8
# Clean-up APT
#RUN rm -rf /var/lib/apt/lists/*

# Customize bash prompt to honor CLI sandbox hostname
RUN cat <<'EOF' >> /home/ubuntu/.bashrc
# CLI sandbox prompt override
if [[ $- == *i* ]] && [ -n "${CLI_SANDBOX_HOSTNAME-}" ] && [[ "$PS1" == *\\h* ]]; then
    PS1="${PS1//\\h/${CLI_SANDBOX_HOSTNAME}}"
fi

# Disable mouse capture in opencode
export OPENCODE_DISABLE_MOUSE=1
EOF

COPY setup-host-user.sh /usr/local/bin/setup-host-user.sh
RUN chmod 755 /usr/local/bin/setup-host-user.sh

ENV TERM=xterm-256color

WORKDIR /sandbox
ENTRYPOINT ["/sbin/my_init", "--quiet", "--"]
CMD ["tail", "-f", "/dev/null"]
