Validate JWT and create headers from claims

#####
# 1 #
#####

#We need to create an Upstream representing Keycloak

kubectl apply --context ${CLUSTER1} -f - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: keycloak
  namespace: gloo-system
spec:
  static:
    hosts:
      - addr: ${HOST_KEYCLOAK}
        port: ${PORT_KEYCLOAK}
EOF

#####
# 2 #
#####

#Create a VirtualHostOption to validate the JWT token and extract the email claim

kubectl apply --context ${CLUSTER1} -f - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualHostOption
metadata:
  name: jwt
  namespace: gloo-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
    namespace: gloo-system
    sectionName: https-httpbin
  options:
    jwtStaged:
      beforeExtAuth:
        providers:
          keycloak:
            issuer: ${KEYCLOAK_URL}/realms/workshop
            tokenSource:
              headers:
              - header: jwt
            jwks:
              remote:
                url: ${KEYCLOAK_URL}/realms/workshop/protocol/openid-connect/certs
                upstreamRef:
                  name: keycloak
                  namespace: gloo-system
            claimsToHeaders:
            - claim: email
              header: X-Email
EOF

#####
# 3 #
#####

#Try accessing the httpbin application without any token.
#You should get a Jwt is missing error message.

curl -k https://httpbin.cluster1.${_SANDBOX_ID}.instruqt.io/get

#####
# 4 #
#####

#Get a JWT and use that JWT to access httpbin
#You should see a new X-Email header added to the request with the value user1@example.com

export USER1_COOKIE_JWT=$(curl -Ssm 10 --fail-with-body \
  -d "client_id=gloo-ext-auth" \
  -d "client_secret=hKcDcqmUKCrPkyDJtCw066hTLzUbAiri" \
  -d "username=user1" \
  -d "password=password" \
  -d "grant_type=password" \
  "$KEYCLOAK_URL/realms/workshop/protocol/openid-connect/token" |
  jq -r .access_token)

#Decode JWT

jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "$USER1_COOKIE_JWT"

curl -k https://httpbin.cluster1.${_SANDBOX_ID}.instruqt.io/get -H "jwt: ${USER1_COOKIE_JWT}"

#####
# 5 #
#####

#Update the VirtualHostOption to add a RBAC rule to only allow a user with the email user2@solo.io

kubectl apply --context ${CLUSTER1} -f - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualHostOption
metadata:
  name: jwt
  namespace: gloo-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: http
    namespace: gloo-system
    sectionName: https-httpbin
  options:
    jwtStaged:
      beforeExtAuth:
        providers:
          keycloak:
            issuer: ${KEYCLOAK_URL}/realms/workshop
            tokenSource:
              headers:
              - header: jwt
            jwks:
              remote:
                url: ${KEYCLOAK_URL}/realms/workshop/protocol/openid-connect/certs
                upstreamRef:
                  name: keycloak
                  namespace: gloo-system
            claimsToHeaders:
            - claim: email
              header: X-Email
    rbac:
      policies:
        viewer:
          principals:
          - jwtPrincipal:
              claims:
                email: user2@solo.io
EOF

#####
# 6 #
#####

#User 1 access denied

curl -k https://httpbin.cluster1.${_SANDBOX_ID}.instruqt.io/get -H "jwt: ${USER1_COOKIE_JWT}"

#Get JWT for User2

export USER2_COOKIE_JWT=$(curl -Ssm 10 --fail-with-body \
  -d "client_id=gloo-ext-auth" \
  -d "client_secret=hKcDcqmUKCrPkyDJtCw066hTLzUbAiri" \
  -d "username=user2" \
  -d "password=password" \
  -d "grant_type=password" \
  "$KEYCLOAK_URL/realms/workshop/protocol/openid-connect/token" |
  jq -r .access_token)

#Decode JWT

jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "$USER1_COOKIE_JWT"

#User 2 access denied

curl -k https://httpbin.cluster1.${_SANDBOX_ID}.instruqt.io/get -H "jwt: ${USER2_COOKIE_JWT}"

kubectl --context ${CLUSTER1} -n gloo-system delete virtualhostoption jwt