Path
===

```ruby
:current => '{PWD}/{TOPLEVEL}/{SUBPATH}',
:user    => '{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}',
:global  => '/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:usr     => '/usr/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:local   => '/usr/local/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:fast    => '/fast/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:cache   => '/cache/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:bulk    => '/bulk/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
:lib     => '{LIBDIR}/{TOPLEVEL}/{SUBPATH}',
:scout_gear => File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}/{SUBPATH}"),
:tmp     => '/tmp/{PKGDIR}/{TOPLEVEL}/{SUBPATH}',
:default => :user
```

# tags
{PKGDIR}
{LIBDIR}
{RESOURCE}
{HOME}
{PWD}
{TOPLEVEL}
{SUBPATH}
{BASENAME}
{PATH}
{MAPNAME}
{REMOVE}
