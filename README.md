# Puppet module for removing Ubuntu advertising

[![CI](https://github.com/bwitt/puppet-unspamify/actions/workflows/ci.yml/badge.svg)](https://github.com/bwitt/puppet-unspamify/actions/workflows/ci.yml)
[![Puppet Forge](https://img.shields.io/puppetforge/v/bwitt/unspamify.svg)](https://forge.puppet.com/modules/bwitt/unspamify)
[![Puppet Forge - downloads](https://img.shields.io/puppetforge/dt/bwitt/unspamify.svg)](https://forge.puppet.com/modules/bwitt/unspamify)
[![Puppet Forge - scores](https://img.shields.io/puppetforge/f/bwitt/unspamify.svg)](https://forge.puppet.com/modules/bwitt/unspamify)
[![License](https://img.shields.io/github/license/bwitt/puppet-unspamify.svg)](https://github.com/bwitt/puppet-unspamify/blob/main/LICENSE)

## Table of Contents

* [Description](#description)
* [Usage](#usage)
* [Reference](#reference)
* [Limitations](#limitations)
* [Development](#development)
* [Author](#author)

## Description

This module applies the recommendations from
[UnspamifyUbuntu](https://github.com/Skyedra/UnspamifyUbuntu) to remove
advertising from Ubuntu:

* Replaces `ubuntu-pro-client` / `ubuntu-advantage-tools` with the
  `fake-ubuntu-advantage-tools` stub package, which removes the
  "Try Ubuntu Pro" messages from APT. The stub ships minimal Python modules so
  update-manager and software-properties keep working.
* Removes the cached ESM announcement shown at login.
* Removes the APT hook (`/etc/apt/apt.conf.d/20apt-esm-hook.conf`) that tries
  to start `apt-news.service` and `esm-cache.service`.
* Disables dynamic MOTD news (`ENABLED=0` in `/etc/default/motd-news`).
* Optionally patches `apt_check.py` to stop the "ESM Apps is not enabled"
  login messages.
* Optionally keeps `distro-info`, which otherwise becomes an autoremove
  candidate.

## Usage

Apply the defaults:

```puppet
include unspamify
```

Keep `distro-info` and patch `apt_check.py` too:

```puppet
class { 'unspamify':
  keep_distro_info => true,
  patch_apt_check  => true,
}
```

Or with Hiera:

```yaml
unspamify::keep_distro_info: true
unspamify::patch_apt_check: true
```

Don't use this module on hosts that need Ubuntu Pro (ESM, Livepatch, etc.):
`replace_ua_tools` removes the Pro client. Set it to `false` to keep the
client while still disabling MOTD news and the APT hook.

## Reference

See [REFERENCE.md](REFERENCE.md).

## Limitations

* Ubuntu only; the class fails on any other OS. Tested on 22.04, 24.04 and
  26.04.
* `disable_motd_news` installs `motd-news-config` (normally pulled in by
  `ubuntu-server`) so `/etc/default/motd-news` always exists and stays
  disabled.
* `patch_apt_check` edits `/usr/lib/update-notifier/apt_check.py`, which is
  owned by `update-notifier-common`. A package upgrade restores the original
  file and the next Puppet run patches it again. The original is saved as
  `apt_check.py.orig`.

## Development

Unit tests and static checks:

```sh
bundle install
bundle exec rake test
```

Acceptance tests run in Docker with Beaker:

```sh
BEAKER_PUPPET_COLLECTION=openvox8 \
BEAKER_SETFILE=ubuntu2404-64 \
bundle exec rake beaker
```

Regenerate `REFERENCE.md` after changing parameters:

```sh
bundle exec rake strings:generate:reference
```

## Author

This module is written and maintained by [Brian Witt](https://github.com/bwitt)
and released under the MIT license; see [LICENSE](LICENSE).

It's based on [UnspamifyUbuntu](https://github.com/Skyedra/UnspamifyUbuntu) by
Skye. `files/fake-ubuntu-advantage-tools.deb` is redistributed unmodified from
that project under the MIT license; see
[files/fake-ubuntu-advantage-tools.LICENSE](files/fake-ubuntu-advantage-tools.LICENSE).
