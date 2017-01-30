#!/bin/bash

set -eo pipefail
if [[ "$TRACE" ]]; then
    : ${START_TIME:=$(date +%s)}
    export START_TIME
    export PS4='+ [TRACE $BASH_SOURCE:$LINENO][ellapsed: $(( $(date +%s) -  $START_TIME ))] '
    set -x
fi

debug() {
  [[ "$DEBUG" ]] && echo "-----> $*" 1>&2
}

index_html() {
    cat > index.html <<EOF
<html xmlns="http://www.w3.org/1999/xhtml" >
<head>
    <title>$MYDOMAIN</title>
</head>
<body>
  <h1>Welcome to $MYDOMAIN</h1>
  <p>soon ...</p>
</body>
</html>
EOF
}


redirect_www() {
  cat <<EOF
{
  "RedirectAllRequestsTo": {
    "HostName": "$MYDOMAIN",
    "Protocol": "http"
  }
}
EOF
}

create_buckets() {
    declare desc="creates 2 buckets www and base"
    declare redirectFile=$1

    debug "$desc"
    for bucket in $MYDOMAIN www.$MYDOMAIN; do
        aws s3 mb s3://$bucket
        index_html
        aws s3 cp --acl public-read index.html s3://$bucket
        aws s3 website s3://$bucket/ --index-document index.html
        debug "You can open: http://$MYDOMAIN.s3.amazonaws.com/index.html"
    done

    debug "redirect all www.$MYDOMAIN => $MYDOMAIN"
    aws s3api put-bucket-website --bucket www.$MYDOMAIN --website-configuration file://<(redirect_www)
}

recordset_alias() {
    declare domainAlias=$1

    : ${domainAlias:? required}
    cat <<EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "$domainAlias",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$DOMAINID",
          "DNSName": "s3-website.eu-central-1.amazonaws.com.",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
}

create_dns() {
    declare desc="creates route53 hosted zone, and aliases"

    debug "$desc"
    : << KOMMENT
    aws route53 create-hosted-zone \
        --name $MYDOMAIN \
        --caller-reference $(date +%Y-%m-%d--%H%M)
KOMMENT
    
    DOMAINID=$(
        aws route53 list-hosted-zones-by-name --dns-name $MYDOMAIN --query HostedZones[0].Id --out text
    )
    DOMAINID=${DOMAINID##*/}
    
    debug "DomainId: $DOMAINID"

    : << KOMMENT
    aws route53 change-resource-record-sets \
        --hosted-zone-id $DOMAINID \
        --change-batch file://<(recordset_alias "${MYDOMAIN}." )
KOMMENT
    
    debug "Set nameserver at your domain registrar:"
    aws route53 get-hosted-zone --id $DOMAINID --query DelegationSet.NameServers --out text|xargs -n 1
}

main() {
  : ${DEBUG:=1}
  : ${MYDOMAIN:? reuired}

  #create_buckets
  create_dns
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@" || true
