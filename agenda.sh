# deploy kyma from branch jakkab:ORY-versions-bump (https://github.com/kyma-project/kyma/pull/5290)

# cel zadania
  - dodanie obsługi tablicy mutatorów
  - dodanie mutatora 'hydrator', którego celem jest modyfikacja obiektu authenticationSession (czyli obiektu przechowującego dodatkowe dane dla danego requestu) przy użyciu zewnętrznego serwisu
  - obsługa go template w mutatorze 'id_token' - niedokończone ponieważ w środę 🍍 zażądał zmian, w związku z tym demuję powyższe dwa

# demo będzie polegało na wystawieniu przykładowego serwisu modyfikującego authenticationSession, oraz stworzeniu ruli, która z niego korzysta aby ustawiać headery

# deploy lambda for showing headers (set lambda name to 'lambda')
module.exports = { main: function (event, context) {
    console.log("Request arrived! headers:")
    const headers = event.extensions.request.headers;
    for (let k of Object.keys(headers)){
        console.log(`> "${k}": ${headers[k]}`);
    } 
    return "OK!";
}}

# in new teminal get logs from lambda
kc logs lambda-87758756f-xj4p4 lambda -f
# or
kc logs -l app=lambda -c lambda

# create virtualservice for lambda
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: lambda-proxy
  namespace: kyma-system
spec:
  gateways:
  - kyma-gateway
  hosts:
  - lambda-proxy.kyma.local
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

# add entry to /etc/hosts
sudo vim /etc/hosts
# paste lambda-proxy.kyma.local at the end

# check if the oathkeeper works for now
curl https://lambda-proxy.kyma.local -vk
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
    url: <http|https>://lambda-proxy.kyma.local/lambda
  authenticators:
    - handler: anonymous
  authorizer:
    handler: allow
  mutators:
    - handler: hydrator
      config:
        api:
          url: http://api.default.svc.cluster.local:8080
    - handler: header
      config:
        headers:
          X-sth: "{{ print .Extra.foo }}"
          X-sth-nested: "{{ print .Extra.boo.bar }}"
EOF

# check if the rule propagated to oathkeeper (from inside of k8s cluster)
curl ory-oathkeeper-api.kyma-system:4456/rules

# check if oathkeeper handle the rule properly
curl https://lambda-proxy.kyma.local/lambda -vk

# get logs from lambda to show, that proper headers were set
kc logs -l app=lambda -c lambda

# get logs from sample api to show the payload from/to oathkeeper
kc logs -l app=api -c app