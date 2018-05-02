Puppet Singularity
===

A Puppet Dashboard optimized for throughput and efficient retention written in Ruby and based on Rack.

Intent
---
Archive and present Puppet reports via a UI using as few resources as possible.

History
---
We used Sodabrew's Puppet Dashboard and it served us well until our system grew past its capabilities.  8GB of memory, a 200GB disk, and 10 cores on a VM was not enough to store a weeks worth of Puppet reports.  Throughput was also an issue as the parser simply couldn't keep up with 3MB+ reports across 1500 VMs running Puppet every 30 minutes.

Techniques
---
Puppet Singularity maintains report metadata of every report that comes in, but deduplicates unchanged reports, only maintaining the most current.
Puppet Singularity was developed on a 2 core, 2GB RAM, and 30 GB storage VM in order to optimize to the smallest VM in our infrastructure.  Even at our scale, this application keeps up in real time and only experiences noticeable load when rendering reports.

Performance
---
Puppet Singularity, under production load, averaged 0.25 seconds per request (including users browsing - the longer running and more intensive requests).  Maximum was 19.5 seconds and minimum was 0.02 seconds.  Sample size: 1,048,575 requests.
Over the course of development, memory utilization never went over 1GB and averaged about 0.5GB.
For perspective, our production Puppet reports range from a few KB to 4MB+, every 40 minutes from 1700+ nodes.

Dependencies (14.04)
---
```
sudo apt-get install git apache2 libapache2-mod-passenger postgresql ruby-pg ruby-archive-tar-minitar ruby-safe-yaml ruby-rack
```

Provisioning (Tested on Ubuntu 14.04)
---
You'll need to configure an Apache VirtualHost with `PassengerEnabled on`.
```
cd /opt && git clone <REPO>
mkdir /var/puppet-singularity && chown nobody /var/puppet-singularity
touch /var/log/singularity.log && chown nobody /var/log/singularity.log
mv /opt/puppet-singularity/puppet-singularity.yml.example /etc/puppet-singularity.yml
```
Users created here will need to be altered in /etc/puppet-singularity.yml:
```
su -c "/usr/bin/psql -c \"CREATE DATABASE singularity;\"" postgres
su -c "psql -c \"CREATE ROLE singularity WITH PASSWORD 'singularity' INHERIT LOGIN;\"" postgres
su -c "psql -c \"GRANT ALL ON DATABASE singularity TO singularity;\"" postgres
```

Debugging
---
Curl, by default, will strip newline characters when trying to post a demo report.  Use `--data-binary` to bypass the issue:
```bash
cat report.yaml | curl -X POST --data-binary @- http://hostname/upload
zcat report.yaml.gz | curl -X POST --data-binary @- http://hostname/upload
```
