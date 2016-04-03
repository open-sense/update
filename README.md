opensense update utilities
=========================

This is a collection of firmware upgrade tools specifically written
for opensense based on FreeBSD ideas (kernel and base sets) and tools
(pkg(8) and freebsd-update(8)).

opensense-update
===============

opensense-update(8) unifies the update process into a single tool
usable from the command line. Since opensense uses FreeBSD's package
manager, but not the native upgrade mechanism, an alternative way
of doing base and kernel updates needed to be introduced.

The process relies on signature verification for all moving parts
(packages and sets) by plugging into pkg(8)'s native verification
mechanisms.

The utility was first introduced in February 2015.

opensense-bootstrap
==================

opensense-bootstrap(8) is a tool that can completely reinstall a
running system in place for a thorough factory reset or to restore
consistency of all the opensense files.  It can also wipe the
configuration directory, but won't do that by default.

It will automatically pick up the latest available version and
build a chain of trust by using current package fingerprints -> CA
root certificates -> HTTPS -> opensense package fingerprints.

What it will also do is turn a supported stock FreeBSD 10 release into
an opensense installation, given that UFS was used to install the
root file system.

The utility was first introduced in November 2015.

opensense-sign && opensense-verify
================================

opensense-sign(8) and opensense-verify(8) sign and verify arbitrary
files using signature verification methods available by pkg(8),
so that a single key store can be used for packages and sets.

opensense-verify(8) is almost entirely based on the pkg bootstrap
code present in the FreeBSD 10 base, but may be linked against
either OpenSSL or LibreSSL from ports.

Both utilities were first introduced in December 2015.
