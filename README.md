# letsencrypt-elb
Simple ruby script for provisioning automation of Let's Encrypt certificates in AWS infrastructure using AWS Route53 and AWS ElasticLoadBalancer. Script is using official acme-client ruby gem for communication with Let's encrypt servers.

## Features
1. Creates new private acme key for communication with acme servers (existing acme key can be used also)
2. Generates new certificates (SAN certificates supported). Using DNS challenge automation with Route53
3. Can run as a daemon or from cron. Automatically renew expiring certificates and provision them into AWS ElasticLoadBalancer
4. Updates ELB certificate listeners with updated certificate or create new HTTPS listener when needed
5. Certificate KEY files are never stored on file system, only uploaded to AWS.

## How does it work
Script create new acme private certificate and generate new server certificates, or renew expiring ones, based on provided configuration using Route53 automation for DNS challenge verification. All certificates are stored locally (only cert files) and are used for expiration checks. New certificates are then attached to configured ELB listeners.

## Configuration
Configuration file is stored in config.yaml. Default configuration section is `default` and can be override by ENV variable `ENCRYPT_ENV`.
```console
$ ENCRYPT_ENV=development ruby letsencrypt.rb
```
Configuratin file example:
```yaml
# letsencrypt-elb configuration file
default: &default
  aws_access_key_id: XXXX # (optional) When ENV variable AWS_ACCESS_KEY_ID is NOT present used this
  aws_secret_access_key: YYYXXXXYYYXXX # (optional) When ENV variable AWS_SECRET_ACCESS_KEY is NOT present used this
  aws_region: eu-central-1 # (required) AWS region
  dns_hook_sleep: 20 # (optional) How many seconds should script wait for DNS changes propagation. Default is 20 which should be ok for Route53
  days_to_expiration: 25 # (optional) Regenerate certificates wich expiring in 25 days. Defautl is 25
  acme_verification_sleep: 2 # (optional) Wait 2 seconds before check status from acme servers. Default 2
  acme_private_key: ./acme_key/private.key # (optional) Acme private key location. Default is ./acme_key/private.key
  dns_hook: AWSRoute53 # (optional) Cheeck Hooks.md for more informations
  acme_endpoint: https://acme-v01.api.letsencrypt.org/ # (required) use https://acme-staging.api.letsencrypt.org/ for testing
  debug: true # Turn on debug messages. Should be turned of in production
  upload_hook: AWSElasticBalancer # (optional) Cheeck Hooks.md for more informations
  acme_email: admin@example.com # (required) - Use this email address when creating new acme private key

  certificates: # (required) Certificate configuration
    example-com: # (required) Certificate identificator.
      domains: # (required) Domain configuration
        example.io: [www.example.io.] # (required) domain.name: [certificate hostnames]
        example2.io: [www, admin.example2.io.] # You can use full domaiin name witn . at the end of the domain or subdomain part of main domain without ending .
      elbs: # (required) ElasticLoadBalancer configuration
        elb-www-examplecom: [443, 8080] # (required) balancer-name-from-aws-console: [Balancer port, Instance port]. Instance port is required only in situation when new listener should be created
    testing-com: # another certificate
      domains:
        testing.io: [www]
      elbs:
        elb-www-testingcom: [443, 3128]

development:
  <<: *default
  debug: true
  acme_endpoint: https://acme-staging.api.letsencrypt.org/
```
## AWS credentials
AWS credentials should be set by standard AWS ENV variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Optionally in config.yaml file. AWS region has to be set in config.yaml file. Current version supports only ONE AWS identity and region.

Scripts needs to have some specific AWS permision to manipulate with AWS resources. Minimal user policy needed for script to run properly:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:GetChange",
                "route53:GetChangeDetails",
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:SetLoadBalancerListenerSSLCertificate",
                "elasticloadbalancing:CreateLoadBalancerListeners"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "iam:DeleteServerCertificate",
                "iam:UploadServerCertificate"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
Resource part of policy can be limited only to managed zones and balancers to increase overall security.

## Usage
Script can be run as a daemon which check expiring certificates every day
```console
$ ruby letsencrypt.rb -d
```
or run only once without -d option
```console
$ ruby letsencrypt.rb
```

Script saves generated certificates to './certs' directory and using these certificates for expiration checking. Don't empty this directory if you don't want to re-generate all certificates.
