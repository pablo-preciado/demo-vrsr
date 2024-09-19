# Demo Vrsr

Use this demo: https://demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.ocp4-acm-hub-rhpds.prod&utm_source=webapp&utm_medium=share-link

You can get the ssh keys from this website: https://www.wpoven.com/tools/create-ssh-key

Get your pull secret from this site: https://cloud.redhat.com/openshift/install/pull-secret

Copy the file ```vars``` to a new file called ```my-vars```, fill this new file with your variable values. Note that the file ```my-vars``` will be excluded from git so your secrets won't be exposed.

Log into your openshift cluster before running the script.

Now execute the setup-script.sh:

```
chmod +x setup-script.sh
./setup-script.sh
```