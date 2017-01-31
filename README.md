Sometimes you just want to quickly register a domain name, and display an index.html hosted on s3.
Normally you perform a lot of manual steps:
- go to a domain registar (godaddy or similar), register the domain name
- create s3 buckets which can hosts the html files, usually example.com and www.example.com at minimum
- set up thos buckets permisiion to be public-readable
- enable website-hosting on those buckets
- set redirect for www.example.com to example.com
- create a hosted zone in route53
- create alias records (A entries) pointing to s3 buckets

The first time it took me about a day to get it working, so this repo provides a simple script to
automate the whole process.
