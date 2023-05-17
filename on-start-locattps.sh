DIR="/app"
PRIVATE="${DIR}/.private"
STATUS_EXT="status"
CONF_NAME=locattps.yml
CONF_FILE="${DIR}/${CONF_NAME}"
ROOT_CERT_BASE=""
ROOT_PREFIX=""

clean_all_states() {
    rm -f "${DIR}"/*."${STATUS_EXT}"
}

set_state() {
    NAME="${1}"
    touch "${DIR}/__${NAME}__.${STATUS_EXT}"
}

create_dirs() {
    mkdir -p "${PRIVATE}"    
}

create_defaut_conf() {
    cat > "${CONF_FILE}" <<__END__
- listen:
    name: xdemo.127-0-0-1.nip.io
  redirectTo:
    host: 
    port: 
__END__
}

has_root_cert() {
    find "${DIR}"/root-*.crt >/dev/null 2>&1
}

create_key() {
    local key_filename="${1}"
    openssl ecparam -genkey -name prime256v1 -out "${key_filename}"
}

create_req_config() {
    local req_filename="${1}"
    local cn="${2}"
    local is_server="${3}"

  cat >"${req_filename}" <<__END__
[ req ]
distinguished_name     = req_distinguished_name
attributes             = req_attributes
prompt                 = no
output_password        = mypass
__END__

  [ -n "${is_server}" ] && cat >>"${req_filename}" <<__END__
req_extensions         = v3_req
x509_extensions        = v509
__END__

  cat >>"${req_filename}" <<__END__

[ req_distinguished_name ]
C                      = xx
ST                     = none
L                      = none
O                      = locattps
OU                     = none
CN                     = ${cn}
emailAddress           = none

[ req_attributes ]
challengePassword      = A challenge password
__END__

  if [ -n "${is_server}" ] ; then
    cat >>"${req_filename}" <<__END__
[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

# Some CAs do not yet support subjectAltName in CSRs.
# Instead the additional names are form entries on web
# pages where one requests the certificate...
subjectAltName          = @alt_names

[ v509 ]
subjectAltName          = @alt_names

[alt_names]
__END__

    counter=1
    for alt_name in ${cn} ; do
      echo "DNS.${counter} = ${alt_name}" >> "${req_filename}"
      [[ ${alt_name} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && echo "IP.${counter} = ${alt_name}" >> "${req_filename}"
      let counter+=1
    done
  fi

}

create_csr() {
    local csr_filename="${1}"
    local key_filename="${2}"
    local req_filename="${3}"

    # echo openssl req -config "${req_filename}" -new -key "${key_filename}" -out "${csr_filename}"
    openssl req -config "${req_filename}" -new -key "${key_filename}" -out "${csr_filename}"
}

sign_root() {
    local crt_filename="${1}"
    local csr_filename="${2}"
    local key_filename="${3}"
    openssl x509 -req -in "${csr_filename}" -signkey "${key_filename}" -out "${crt_filename}"
}

sign_server() {
    local crt_filename="${1}"
    local csr_filename="${2}"
    local req_filename="${3}"
    local root_crt_filename="${4}"
    local root_key_filename="${5}"
    openssl x509 -req -in "${csr_filename}" -CA "${root_crt_filename}" -CAkey "${root_key_filename}" -CAcreateserial -out "${crt_filename}" -extensions v3_req -extfile "${req_filename}"
}

get_sum() {
    local filename="${1}"
    sha256sum "${filename}" | sed -e 's/ .*//'
}

create_root() {
    ROOT_CERT_BASE="root-$(date +"%Y-%m-%d")-$(openssl rand -hex 4)"
    echo "poide" > "${DIR}/${ROOT_CERT_BASE}.crt"
    rm -rf "${PRIVATE}/roots"
    ROOT_PREFIX="${PRIVATE}/roots/${ROOT_CERT_BASE}"
    mkdir -p "${ROOT_PREFIX}"
    create_key "${ROOT_PREFIX}/root.key"
    create_req_config "${ROOT_PREFIX}/root.req" "Z locattps ${ROOT_CERT_BASE}"
    create_csr "${ROOT_PREFIX}/root.csr" "${ROOT_PREFIX}/root.key" "${ROOT_PREFIX}/root.req"
    sign_root "${ROOT_PREFIX}/root.crt" "${ROOT_PREFIX}/root.csr" "${ROOT_PREFIX}/root.key"
    cp "${ROOT_PREFIX}/root.crt" "${DIR}/${ROOT_CERT_BASE}.crt"
    echo "Root certificate [${ROOT_CERT_BASE}] created..."
}

create_server_cert() {
    local server_name="${1}"
    local server_dir="${ROOT_PREFIX}/servers/${server_name}"
    if [ ! -f "${server_dir}/server.crt" ]
    then
        rm -rf "${server_dir}"
        mkdir -p "${server_dir}"
        create_key "${server_dir}/server.key"
        create_req_config "${server_dir}/server.req" "${server_name}" "1"
        create_csr "${server_dir}/server.csr" "${server_dir}/server.key" "${server_dir}/server.req"
        sign_server "${server_dir}/server.crt" "${server_dir}/server.csr" "${server_dir}/server.req" "${ROOT_PREFIX}/root.crt" "${ROOT_PREFIX}/root.key"
        openssl ec -in "${server_dir}/server.key" -outform PEM -out "${server_dir}/server_ec.key"
        openssl pkcs8 -topk8 -inform PEM -in "${server_dir}/server_ec.key" -outform PEM -nocrypt -out "${server_dir}/server_ec_pkcs8.key"

        # openssl dhparam -out "${server_dir}/server.dhparams.pem" 4096
        echo "Certificate for server [${server_name}] created"
    else
        echo "Certificate for server [${server_name}] found"
    fi
}

ensure_root() {
    if has_root_cert
    then
        ROOT_CERT=$(find "${DIR}"/root-*.crt | sort | tail -n 1)
        ROOT_CERT_NAME="${ROOT_CERT##*/}"
        ROOT_CERT_BASE="${ROOT_CERT_NAME%.*}"
        echo "Found ROOT_CERT [${ROOT_CERT}][${ROOT_CERT_BASE}]"
        ROOT_PREFIX="${PRIVATE}/roots/${ROOT_CERT_BASE}"
        local cert_ok="0"
        if [ -f "${ROOT_PREFIX}/root.crt" ]
        then
            local sum1=$(get_sum "${ROOT_CERT}")
            local sum2=$(get_sum "${ROOT_PREFIX}/root.crt")
            if [ "${sum1}" != "${sum2}" ]
            then
                echo "The root certificate doesn't match the known certificate... Recreating one..."
            else
                cert_ok="1"
            fi
        else
            echo "The root certificate doesn't exists... Recreating one..."
        fi

        if [ "${cert_ok}" != "1" ]
        then
            rm -f "${DIR}"/root-*.crt
            rm -rf "${PRIVATE}/roots"
            create_root
        else
            echo "Root certificate [${ROOT_CERT_BASE}] seems ok..."
        fi
    else
        create_root
    fi
}

read_conf() {
    n_conf=$(yq .[].listen.name "${CONF_FILE}" | wc -l)
    echo "Found [${n_conf}] conf items"
    rm -rf "/etc/nginx/certs"
    mkdir -p "/etc/nginx/certs"

    rm -rf "/etc/nginx/conf.d"
    mkdir -p "/etc/nginx/conf.d"
    let i=0

    cat > "/etc/nginx/conf.d/00-common-conf.conf" <<__END__
map \$http_x_forwarded_proto \$proxy_x_forwarded_proto {
  default \$http_x_forwarded_proto;
  ''      \$scheme;
}
map \$http_x_forwarded_port \$proxy_x_forwarded_port {
  default \$http_x_forwarded_port;
  ''      \$server_port;
}
map \$http_upgrade \$proxy_connection {
  default upgrade;
  '' close;
}
server_names_hash_bucket_size 128;
map \$scheme \$proxy_x_forwarded_ssl {
  default off;
  https on;
}
gzip_types text/plain text/css application/javascript application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
__END__

    while [ "${i}" -lt "${n_conf}" ]
    do
        echo "conf [${i}]"
        listen_name=$(yq ".[${i}].listen.name" "${CONF_FILE}")
        listen_port=$(yq ".[${i}].listen | .port // 443" "${CONF_FILE}")
        redir_host=$(yq ".[${i}].redirectTo.host" "${CONF_FILE}")
        redir_port=$(yq ".[${i}].redirectTo.port" "${CONF_FILE}")
        echo " => [${listen_name}][${listen_port}][${redir_host}][${redir_port}]"
        create_server_cert "${listen_name}"

        # cp "${ROOT_PREFIX}/root.crt" "/etc/nginx/certs/${listen_name}.crt"
        # cat "${ROOT_PREFIX}/servers/${listen_name}/server.crt" >> "/etc/nginx/certs/${listen_name}.crt"
        cp "${ROOT_PREFIX}/servers/${listen_name}/server.crt" "/etc/nginx/certs/${listen_name}.crt"
        # cat "${ROOT_PREFIX}/root.crt" >> "/etc/nginx/certs/${listen_name}.crt"
        cp "${ROOT_PREFIX}/servers/${listen_name}/server_ec_pkcs8.key" "/etc/nginx/certs/${listen_name}.key"

        ## echo "=========="
        ## echo "${listen_name}.crt"
        ## echo "----------"
        ## cat "/etc/nginx/certs/${listen_name}.crt"
        ## echo "=========="
        ## echo "${listen_name}.key"
        ## echo "----------"
        ## cat "/etc/nginx/certs/${listen_name}.key"

        # cp "${ROOT_PREFIX}/servers/${listen_name}/server.dhparams.pem" "/etc/nginx/certs/${listen_name}.dhparams.pem"

        chown nginx:nginx "/etc/nginx/certs/${listen_name}.crt" "/etc/nginx/certs/${listen_name}.key"
        chmod 400 "/etc/nginx/certs/${listen_name}.crt" "/etc/nginx/certs/${listen_name}.key"

        local confid="${i}-${listen_name}-${redir_host}-${redir_port}"
        local confname="/etc/nginx/conf.d/conf-${confid}.conf"
        cat > "${confname}" <<__END__
server {
  server_name ${listen_name};
  listen ${listen_port} ssl http2 ;
  access_log /var/log/nginx/access-${confid}.log combined;
  add_header 'Access-Control-Allow-Origin' '*';
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_ciphers TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-GCM-SHA384;
  ssl_session_timeout 5m;
  ssl_session_cache shared:SSL:50m;
  ssl_session_tickets off;
  ssl_certificate /etc/nginx/certs/${listen_name}.crt;
  ssl_certificate_key /etc/nginx/certs/${listen_name}.key;
  location / {
      proxy_pass http://${redir_host}:${redir_port};
      proxy_http_version 1.1;
      proxy_buffering off;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$proxy_connection;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
      proxy_set_header X-Forwarded-Ssl \$proxy_x_forwarded_ssl;
      proxy_set_header X-Forwarded-Port \$proxy_x_forwarded_port;
      proxy_set_header Proxy '';
      proxy_pass_request_headers on;
  }
}
__END__

        let i="${i}+1"
    done
}

chmod 777 "${PRIVATE}"

create_dirs
clean_all_states


if [ -f "${CONF_FILE}" ]
then
    ensure_root
    read_conf
else
    create_defaut_conf
    echo "You need to edit locattps.yml file"
    exit 1
fi

chmod 000 "${PRIVATE}"