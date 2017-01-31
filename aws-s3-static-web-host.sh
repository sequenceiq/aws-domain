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

        if aws s3api get-bucket-location --bucket $bucket;then
            debug "bucket: $bucket already exsts ..."
            continue
        fi
        aws s3 mb s3://$bucket
        index_html
        aws s3 cp --acl public-read index.html s3://$bucket
        aws s3 website s3://$bucket/ --index-document index.html
        debug "You can open: http://$MYDOMAIN.s3.amazonaws.com/index.html"
    done

    debug "redirect all www.$MYDOMAIN => $MYDOMAIN"
    aws s3api put-bucket-website --bucket www.$MYDOMAIN --website-configuration file://<(redirect_www)
}

# For DNS aliases use simple A records and point to region specific s3 endpoint
# The region specific s3 endpoint dns nameserver's corresponding HostedZoneIds listed:
#   http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_website_region_endpoints
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
          "HostedZoneId": "Z21DNDUVLTQW6Q",
          "DNSName": "s3-website.eu-central-1.amazonaws.com.",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
}

get_hosted_zone_id() {
    aws route53 list-hosted-zones-by-name \
        --dns-name $MYDOMAIN \
        --query HostedZones[0].Id \
        --out text
}

create_dns() {
    declare desc="creates route53 hosted zone, and aliases"

    debug "$desc"

    DOMAINID=$(get_hosted_zone_id)
    if ! [[ "$DOMAINID" ]]; then
        debug "Creating hosted zone for: $MYDOMAIN"
        aws route53 create-hosted-zone \
            --name $MYDOMAIN \
            --caller-reference $(date +%Y-%m-%d--%H%M)
    fi
    
    DOMAINID=$(get_hosted_zone_id)
    DOMAINID=${DOMAINID##*/}
    
    debug "DomainId: $DOMAINID"

    for domainAlias in "${MYDOMAIN}." "www.${MYDOMAIN}."; do
        debug "creating alias for: $domainAlias"
        aws route53 change-resource-record-sets \
            --hosted-zone-id $DOMAINID \
            --change-batch file://<(recordset_alias "${domainAlias}" )
    done

    debug "Set nameserver at your domain registrar:"
    aws route53 get-hosted-zone --id $DOMAINID --query DelegationSet.NameServers --out text|xargs -n 1

    #list AWS hosted domainnames:
    #aws route53domains list-domains --region us-east-1 --query Domains[].DomainName --out text
}

register_json() {
    : ${AutoRenew:=false}
    : ${DurationInYears:=1}
    
    : ${FirstName:? required}
    : ${LastName:? required}
    : ${ContactType:? required}
    : ${OrganizationName:? required}
    : ${AddressLine1:? required}
    : ${AddressLine2:? required}
    : ${City:? required}
    : ${State:? required}
    : ${CountryCode:? required}
    : ${ZipCode:? required}
    : ${PhoneNumber:? required}
    : ${Email:? required}

    cat <<EOF
{
    "DomainName": "$MYDOMAIN",
    "DurationInYears": 1,
    "AutoRenew": ${AutoRenew},
    "AdminContact": {
        "FirstName": "${FirstName}",
        "LastName": "${LastName}",
        "ContactType": "${ContactType}",
        "OrganizationName": "${OrganizationName}",
        "AddressLine1": "${AddressLine1}",
        "AddressLine2": "${AddressLine2}",
        "City": "${City}",
        "CountryCode": "${CountryCode}",
        "ZipCode": "${ZipCode}",
        "PhoneNumber": "${PhoneNumber}",
        "Email": "${Email}"
    },
    "RegistrantContact": {
        "FirstName": "${FirstName}",
        "LastName": "${LastName}",
        "ContactType": "${ContactType}",
        "OrganizationName": "${OrganizationName}",
        "AddressLine1": "${AddressLine1}",
        "AddressLine2": "${AddressLine2}",
        "City": "${City}",
        "CountryCode": "${CountryCode}",
        "ZipCode": "${ZipCode}",
        "PhoneNumber": "${PhoneNumber}",
        "Email": "${Email}"
    },
    "TechContact": {
        "FirstName": "${FirstName}",
        "LastName": "${LastName}",
        "ContactType": "${ContactType}",
        "OrganizationName": "${OrganizationName}",
        "AddressLine1": "${AddressLine1}",
        "AddressLine2": "${AddressLine2}",
        "City": "${City}",
        "CountryCode": "${CountryCode}",
        "ZipCode": "${ZipCode}",
        "PhoneNumber": "${PhoneNumber}",
        "Email": "${Email}"
    },
    "PrivacyProtectAdminContact": true,
    "PrivacyProtectRegistrantContact": true,
    "PrivacyProtectTechContact": true
}
EOF
}

register_domain() {
    declare desc="register domain at AWS"

    local availabilty=$(
        aws route53domains check-domain-availability --region us-east-1  --domain-name $MYDOMAIN --query Availability --out text
    )
    debug "$MYDOMAIN is: $availabilty"

    if [[ "$availabilty" != "AVAILABLE" ]];then
        echo "=====> Upps, you have missed it $MYDOMAIN is $availabilty"
        exit 1
    fi

    register_json > register.json
    aws route53domains register-domain \
        --region us-east-1 \
        --cli-input-json file://register.json
}

main() {
  : ${DEBUG:=1}
  : ${MYDOMAIN:? reuired}

  register_domain
  #create_buckets
  #create_dns
  
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@" || true

