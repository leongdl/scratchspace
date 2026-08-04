# Getting the 3ds Max (and other DCC) installers

Source of truth: the internal `deadline-workstation` skill in the `BealineAIMAgents`
package. The Bealine team keeps DCC installers in a shared S3 bucket:

```
s3://common-bealinerezpackage-resources-bucket/          (us-west-2)
  3dsmax/2024/  3dsmax/2025/  3dsmax/2026/
  blender/  Maya/  Nuke/  vray/  houdini/  redshift/  keyshot/  aftereffects/ ...
```

Contents verified 2026-08-04:

```
3dsmax/2025/3dsMax2025.zip   5,330,575,388 bytes
3dsmax/2025/vray2025.exe     1,269,742,664 bytes
3dsmax/2026/3dsMax2026.zip   5,924,175,827 bytes
3dsmax/2026/vray2026.exe     1,210,116,480 bytes
```

## Access patterns

1. **From this dev box (account 224071664257 credentials):** the bucket policy allows
   the account directly — `update-ada` then plain `aws s3 ls/cp/presign` works. The
   skill documents an `AWS_PROFILE=shared-ro` profile; not needed from this account.

2. **Presigned URL for a worker without S3 permissions** (SSM RunCommand context, or a
   fleet whose role lacks s3:GetObject — BealineE2EFleetRole is such a role):

   ```bash
   aws s3 presign s3://common-bealinerezpackage-resources-bucket/3dsmax/2025/3dsMax2025.zip \
     --expires-in 7200 --region us-west-2
   ```

   Then on the worker: `curl.exe -sS -L -o D:\installers\3dsMax2025.zip "<url>"`.
   Download measured at ~2.5 min for 5.3 GB. **URLs expire (max 7 days with IAM user
   creds, ~an hour-scale with assumed-role session creds since the URL dies with the
   session token). Do not bake presigned URLs into anything long-lived.**

3. **Production host config:** give the fleet role `s3:GetObject` on the installer
   objects and use `aws s3 cp` in the script (the AE sample's pattern; the
   `host-config/3dsmax-2025-pv-cached.ps1` draft ships this way). For the shared
   bucket, cross-account object reads also depend on the bucket policy — if the fleet
   role isn't allowed, copy the installer into a bucket you own:

   ```bash
   aws s3 cp s3://common-bealinerezpackage-resources-bucket/3dsmax/2025/3dsMax2025.zip \
     s3://<your-bucket>/installers/3dsMax2025.zip --region us-west-2
   ```

## Alternative: build the zip yourself

Public instructions for creating the installer zip from Autodesk downloads:
https://github.com/aws-deadline/deadline-cloud-samples/blob/mainline/host_configuration_scripts/3dsmax/README.md

> Autodesk Cloud Rights note: 3ds Max licensing is separate from AWS. Confirm
> entitlements before rendering at scale:
> https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Subscription-Benefits-FAQ-Cloud-Rights.html
