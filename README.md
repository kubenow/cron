![logo](https://github.com/kubenow/KubeNow/blob/master/img/logo_wide_50dpi.png)

Collection of bash scripts for most common Cloud providers (e.g. GCE, AWS, OpenStack and Azure) in order to clean up both testing and old KubeNow images.

[![Build Status](https://travis-ci.org/kubenow/image.svg?branch=master)](https://travis-ci.org/kubenow/cron)

## Cleaning Up Images

This collection of cleaning up scripts have been created keeping in mind our custom process for building KubeNow images (and our convention of tagging them). However they may possibly be adapted for cleaning up old prebuilt images within your provider environments. Bear in mind that you need to either source or import somehow your own cloud credentials before running these snippets of code.

## Image Building

KubeNow uses prebuilt images to speed up the deployment. Image continous integration is defined in this repository: https://github.com/kubenow/image.

The images are exported on AWS and GCE:

- `https://storage.googleapis.com/kubenow-images/kubenow-v<version-without-dots>.tar.gz`
- `https://s3.amazonaws.com/kubenow-us-east-1/kubenow-v<version-without-dots>.qcow2`

Please refer to this page to figure out the image version: https://github.com/kubenow/image/releases. It is important to point out that the image versioning is now disjoint from the main KubeNow repository versioning. The main reason lies in the fact that pre-built images require less revisions and updates compared to the main KubeNow package.