#!/usr/bin/env bash
set -e
set +x

# Generate temporary keystore password
CERTS_STORE_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
export CERTS_STORE_PASSWORD

# Create dir where keystores and truststores will be stored
mkdir -p /tmp/kafka/clusters

# Import cluster certificates into keystores and truststores
echo "Preparing MirrorMaker 2.0 cluster truststores and keystores"

declare -A TLS_AUTH_CERTS
if [ -n "$KAFKA_MIRRORMAKER_2_TLS_AUTH_CERTS_CLUSTERS" ]; then
    IFS=$'\n' read -rd '' -a TLS_AUTH_CERTS_CLUSTERS <<< "$KAFKA_MIRRORMAKER_2_TLS_AUTH_CERTS_CLUSTERS" || true
    for cluster in "${TLS_AUTH_CERTS_CLUSTERS[@]}"
    do
        IFS='=' read -ra TLS_AUTH_CERT_CLUSTER <<< "${cluster}" || true
        TLS_AUTH_CERTS["${TLS_AUTH_CERT_CLUSTER[0]}"]="${TLS_AUTH_CERT_CLUSTER[1]}"
    done
fi

declare -A TLS_AUTH_KEYS
if [ -n "$KAFKA_MIRRORMAKER_2_TLS_AUTH_KEYS_CLUSTERS" ]; then
    IFS=$'\n' read -rd '' -a TLS_AUTH_KEYS_CLUSTERS <<< "$KAFKA_MIRRORMAKER_2_TLS_AUTH_KEYS_CLUSTERS" || true
    for cluster in "${TLS_AUTH_KEYS_CLUSTERS[@]}"
    do
        IFS='=' read -ra TLS_AUTH_KEY_CLUSTER <<< "${cluster}" || true
        TLS_AUTH_KEYS["${TLS_AUTH_KEY_CLUSTER[0]}"]="${TLS_AUTH_KEY_CLUSTER[1]}"
    done
fi

declare -A TRUSTED_CERTS
if [ -n "$KAFKA_MIRRORMAKER_2_TRUSTED_CERTS_CLUSTERS" ]; then
    IFS=$'\n' read -rd '' -a TRUSTED_CERTS_CLUSTERS <<< "$KAFKA_MIRRORMAKER_2_TRUSTED_CERTS_CLUSTERS" || true
    for cluster in "${TRUSTED_CERTS_CLUSTERS[@]}"
    do
        IFS='=' read -ra TRUSTED_CERTS_CLUSTER <<< "${cluster}" || true
        TRUSTED_CERTS["${TRUSTED_CERTS_CLUSTER[0]}"]="${TRUSTED_CERTS_CLUSTER[1]}"
    done
fi

if [ -n "$KAFKA_MIRRORMAKER_2_CLUSTERS" ]; then
    IFS=';' read -ra CLUSTERS <<< "$KAFKA_MIRRORMAKER_2_CLUSTERS" || true
    for clusterAlias in "${CLUSTERS[@]}"
    do
        echo "Preparing MirrorMaker 2.0 truststores and keystores for cluster ${clusterAlias}"
        echo "  with trusted certs ${TRUSTED_CERTS["${clusterAlias}"]}"
        echo "  with tls auth certs ${TLS_AUTH_CERTS["${clusterAlias}"]}"
        echo "  with tls auth keys ${TLS_AUTH_KEYS["${clusterAlias}"]}"
        # $1 = trusted certs, $2 = TLS auth cert, $3 = TLS auth key, $4 = truststore path, $5 = keystore path, $6 = certs and key path
        ./kafka_mirror_maker_tls_prepare_certificates.sh \
            "${TRUSTED_CERTS["${clusterAlias}"]}" \
            "${TLS_AUTH_CERTS["${clusterAlias}"]}" \
            "${TLS_AUTH_KEYS["${clusterAlias}"]}" \
            "/tmp/kafka/clusters/${clusterAlias}.truststore.p12" \
            "/tmp/kafka/clusters/${clusterAlias}.keystore.p12" \
            "/opt/kafka/mm2-certs/${clusterAlias}" \
            "/opt/kafka/mm2-oauth-certs/${clusterAlias}" \
            "/tmp/kafka/clusters/${clusterAlias}-oauth.truststore.p12"
    done
    echo "Preparing MirrorMaker 2.0 cluster truststores is complete"
fi

# Generate and print the connector config file
echo "Creating connector configuration:"
./kafka_mirror_maker_2_connector_config_generator.sh | tee /tmp/strimzi-mirrormaker2-connector.properties | sed -e 's/sasl.jaas.config=.*/sasl.jaas.config=[hidden]/g' -e 's/password=.*/password=[hidden]/g'
echo ""

if [ -n "$STRIMZI_JAVA_SYSTEM_PROPERTIES" ]; then
    export KAFKA_OPTS="${KAFKA_OPTS} ${STRIMZI_JAVA_SYSTEM_PROPERTIES}"
fi

exec ./kafka_connect_run.sh
