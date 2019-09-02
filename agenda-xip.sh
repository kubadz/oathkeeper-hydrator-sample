# deploy kyma from master (previously branch jakkab:ORY-versions-bump (https://github.com/kyma-project/kyma/pull/5290))

# cel zadania
  - dodanie obsługi tablicy mutatorów
  - dodanie mutatora 'hydrator', którego celem jest modyfikacja obiektu authenticationSession (czyli obiektu przechowującego dodatkowe dane dla danego requestu) przy użyciu zewnętrznego serwisu
  - obsługa go template w mutatorze 'id_token'

# demo będzie polegało na wystawieniu przykładowego serwisu dodającego do authenticationSession scope na podstawie otrzymanego headera, a następnie stworzeniu ruli, która z niego korzysta aby przepisać ten scope jako customowy claim w tokenie

# enable id_token mutator in oathkeeper global config, as it is disabled by default
kc edit cm -n kyma-system ory-oathkeeper-config
# change id_token.enabled to `true`
# change id_token.jwks_url to `https://raw.githubusercontent.com/ory/k8s/master/helm/charts/oathkeeper/demo/mutator.id_token.jwks.json`
# restart oathkeeper pod
kc delete pod -n kyma-system -l "app.kubernetes.io/name"=oathkeeper

# deploy lambda for showing jwt payload (set lambda name to 'lambda')
module.exports = { main: function (event, context) {
    console.log("Request arrived!")
    const headers = event.extensions.request.headers;
    let token = headers['authorization'];
    token = token.replace('Bearer ', '');
    const tokenPayloadEncoded = token.split('.')[1];
    const tokenPayload = Buffer.from(tokenPayloadEncoded, 'base64').toString('ascii');
    console.log(tokenPayload);
    return "OK!";
}}

# in new teminal get logs from lambda
kc logs lambda-87758756f-xj4p4 lambda -f
# or
kc logs -l app=lambda -c lambda

# get external ip
export EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{ .status.loadBalancer.ingress[0].ip }')

# create virtualservice for lambda
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: lambda
  namespace: kyma-system
spec:
  gateways:
  - kyma-gateway
  hosts:
  - lambda.$EXTERNAL_IP.xip.io
  http:
  - match:
    - uri:
        regex: /.*
    route:
    - destination:
        host: ory-oathkeeper-proxy
        port:
          number: 4455
EOF

# copy lambda URL
export LAMBDA_URL=$(kubectl get virtualservice lambda -n kyma-system -o jsonpath='{ .spec.hosts[0] }')

# check if the oathkeeper works for now
curl https://$LAMBDA_URL -vk
# should return 404: {"error":{"code":404,"status":"Not Found","request":"474ecda5-d911-458c-9cd5-a607bd413a1a","message":"Requested url does not match any rules"}}

# deploy some app with curl
kc run alpi --image=spotify/alpine -it

# check if there are any rules in oathkeeper (from inside of k8s cluster)
curl ory-oathkeeper-api.kyma-system:4456/rules


# build and deploy sample api
kc apply -f deployment.yaml
# in new terminal get logs from sample-api app
kc logs api-cfcd9685b-q5rjl  app -f
# or
kc logs -l app=api -c app

# create a rule
cat <<EOF | kubectl apply -f -
apiVersion: oathkeeper.ory.sh/v1alpha1
kind: Rule
metadata:
  name: lambda
  namespace: default
spec:
  description: lambda lambda lambda
  upstream:
    url: http://lambda.default.svc.cluster.local:8080
  match:
    methods: ["GET"]
    url: <http|https>://$LAMBDA_URL/
  authenticators:
    - handler: anonymous
  authorizer:
    handler: allow
  mutators:
    - handler: hydrator
      config:
        api:
          url: http://api.default.svc.cluster.local:8080
    - handler: id_token
      config:
        claims: "{\"scope\": \"{{ print .Extra.scopes }}\"}"
EOF

# check if the rule propagated to oathkeeper (from inside of k8s cluster)
curl ory-oathkeeper-api.kyma-system:4456/rules

# check if oathkeeper handle the rule properly
curl https://$LAMBDA_URL -vk
curl https://$LAMBDA_URL -vk -H 'X-group: admin'
curl https://$LAMBDA_URL -vk -H 'X-group: user'
curl https://$LAMBDA_URL -vk -H 'X-group: anonymous'

# get logs from lambda to show, that proper headers were set
kc logs -l app=lambda -c lambda

# get logs from sample api to show the payload from/to oathkeeper
kc logs -l app=api -c app