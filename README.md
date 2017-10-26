![logo](https://github.com/kubenow/KubeNow/blob/master/img/logo_wide_50dpi.png)

[![Build Status](https://travis-ci.org/kubenow/image.svg?branch=master)](https://travis-ci.org/kubenow/cron)

This repository contains KubeNow Travis cron jobs.

## Image cleanup scripts

```
aws_clean_images.sh
aws_del_old_snaps.sh
gce_clean_images.sh
os_clean_images.sh
az_clean_images.sh
```

This collection of cleaning up scripts have been created keeping in mind our custom process for building KubeNow images (and our convention of tagging them). However they may possibly be adapted for cleaning up old prebuilt images within your provider environments. Bear in mind that you need to either source or import somehow your own cloud credentials before running these snippets of code.
