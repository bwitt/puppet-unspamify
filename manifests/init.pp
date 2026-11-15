# @summary Removes advertising from Ubuntu
#
# Implements the recommendations from https://github.com/Skyedra/UnspamifyUbuntu
#
# @param replace_ua_tools
#   Replace ubuntu-advantage-tools with the fake-ubuntu-advantage-tools stub
#   package, which removes the "Try Ubuntu Pro" APT messages. Also removes any
#   cached ESM announcement shown at login.
# @param purge_ua_tools
#   Purge the replaced Pro client packages, removing their leftover config
#   files and the ads cached in /var/lib/ubuntu-advantage. Only applies with
#   replace_ua_tools.
# @param disable_esm_hook
#   Remove the APT hook that tries to start apt-news.service and
#   esm-cache.service after ubuntu-advantage-tools is gone.
# @param disable_motd_news
#   Set ENABLED=0 in /etc/default/motd-news to stop dynamic MOTD ads.
#   Installs motd-news-config, which owns that file.
# @param hide_esm_motd
#   Create /var/lib/update-notifier/hide-esm-in-motd, which tells
#   update-notifier to stop printing the "ESM Apps is not enabled" messages at
#   login. Survives package upgrades.
# @param patch_apt_check
#   Patch /usr/lib/update-notifier/apt_check.py so it no longer prints the
#   "ESM Apps is not enabled" messages at login. Opt-in, because it edits a
#   file owned by update-notifier-common. Only needed with an update-notifier
#   too old for hide_esm_motd.
# @param patch_livepatch_tip
#   Patch /usr/lib/python3/dist-packages/UpdateManager/Dialogs.py so Software
#   Updater stops showing the Livepatch tip (desktop only). Opt-in, because it
#   edits a file owned by update-manager.
# @param disable_apt_news
#   Run `pro config set apt_news=false` to hide APT news on hosts that keep the
#   real Pro client. Requires replace_ua_tools => false.
# @param keep_distro_info
#   Install distro-info and mark it manually installed. ubuntu-advantage-tools
#   was the only package depending on it, so apt would otherwise offer to
#   autoremove it.
#
# @example
#   include unspamify
#
class unspamify (
  Boolean $replace_ua_tools    = true,
  Boolean $purge_ua_tools      = true,
  Boolean $disable_esm_hook    = true,
  Boolean $disable_motd_news   = true,
  Boolean $hide_esm_motd       = true,
  Boolean $patch_apt_check     = false,
  Boolean $patch_livepatch_tip = false,
  Boolean $disable_apt_news    = false,
  Boolean $keep_distro_info    = false,
) {
  if $facts['os']['name'] != 'Ubuntu' {
    fail("${module_name} only supports Ubuntu, not ${facts['os']['name']}")
  }

  if $replace_ua_tools and $disable_apt_news {
    fail("${module_name}: disable_apt_news needs the real Pro client; set replace_ua_tools => false")
  }

  if $replace_ua_tools {
    $deb = '/var/cache/unspamify/fake-ubuntu-advantage-tools.deb'

    file { '/var/cache/unspamify':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { $deb:
      ensure => file,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
      source => "puppet:///modules/${module_name}/fake-ubuntu-advantage-tools.deb",
    }

    # apt-get (not dpkg) resolves the Conflicts and removes
    # ubuntu-advantage-tools in the same transaction.
    exec { 'install fake-ubuntu-advantage-tools':
      provider    => shell,
      command     => "apt-get install -y ${deb}",
      unless      => "dpkg-query -W -f='\${Status}' fake-ubuntu-advantage-tools 2>/dev/null | grep -q '^install ok installed$'",
      environment => ['DEBIAN_FRONTEND=noninteractive'],
      path        => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
      require     => File[$deb],
    }

    file { '/var/lib/ubuntu-advantage/messages/motd-esm-announce':
      ensure  => absent,
      require => Exec['install fake-ubuntu-advantage-tools'],
    }

    if $purge_ua_tools {
      # Names of the replaced packages left in config-files ("rc") state.
      # dpkg, unlike apt, won't swap in the stub that Provides these names.
      $ua_rc = @(CMD/L)
        dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
        ubuntu-advantage-tools ubuntu-pro-client ubuntu-advantage-desktop-daemon \
        2>/dev/null | awk '$1 == "rc" { print $2 }'
        |- CMD

      exec { 'purge ubuntu-advantage-tools':
        provider => shell,
        command  => "${ua_rc} | xargs -r dpkg --purge",
        onlyif   => "${ua_rc} | grep -q .",
        path     => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
        require  => Exec['install fake-ubuntu-advantage-tools'],
      }
    }
  }

  if $disable_apt_news {
    exec { 'disable apt_news':
      command => 'pro config set apt_news=false',
      unless  => "pro config show apt_news | grep -qx 'apt_news False'",
      path    => ['/usr/bin', '/bin'],
    }
  }

  if $disable_esm_hook {
    file { '/etc/apt/apt.conf.d/20apt-esm-hook.conf':
      ensure => absent,
    }
  }

  if $keep_distro_info {
    package { 'distro-info':
      ensure => installed,
    }

    # package can't mark manual, and an auto-installed distro-info would be
    # offered for autoremove once ubuntu-advantage-tools is gone
    exec { 'mark distro-info manual':
      command => 'apt-mark manual distro-info',
      unless  => 'apt-mark showmanual distro-info | grep -qx distro-info',
      path    => ['/usr/bin', '/bin'],
      require => Package['distro-info'],
    }
  }

  if $disable_motd_news {
    package { 'motd-news-config':
      ensure => installed,
    }

    file_line { 'disable motd-news':
      path    => '/etc/default/motd-news',
      line    => 'ENABLED=0',
      match   => '^ENABLED=',
      require => Package['motd-news-config'],
    }
  }

  if $hide_esm_motd {
    # update-notifier-common normally creates this; the marker is harmless
    # without it
    file { '/var/lib/update-notifier':
      ensure => directory,
    }

    file { '/var/lib/update-notifier/hide-esm-in-motd':
      ensure => file,
      notify => Exec['regenerate motd updates-available'],
    }
  }

  if $patch_apt_check {
    $apt_check = '/usr/lib/update-notifier/apt_check.py'

    # sed expressions copied verbatim from the upstream README
    exec { 'patch apt_check.py ESM messages':
      provider => shell,
      command  => @("CMD"/L),
        sed -Ezi.orig \
        -e 's/(def _output_esm_service_status.outstream, have_esm_service, service_type.:\\n)/\\1    return\\n/' \
        -e 's/(def _output_esm_package_alert.*?\\n.*?\\n.:\\n)/\\1    return\\n/' \
        ${apt_check}
        | CMD
      onlyif   => "grep -Pzq 'def _output_esm_service_status\\(outstream, have_esm_service, service_type\\):\\n(?!    return\\n)' ${apt_check}",
      path     => ['/usr/bin', '/bin'],
      notify   => Exec['regenerate motd updates-available'],
    }
  }

  if $hide_esm_motd or $patch_apt_check {
    exec { 'regenerate motd updates-available':
      command     => '/usr/lib/update-notifier/update-motd-updates-available --force',
      onlyif      => 'test -x /usr/lib/update-notifier/update-motd-updates-available',
      path        => ['/usr/bin', '/bin'],
      refreshonly => true,
    }
  }

  if $patch_livepatch_tip {
    $dialogs = '/usr/lib/python3/dist-packages/UpdateManager/Dialogs.py'

    # sed expression copied verbatim from the upstream README
    exec { 'patch Dialogs.py Livepatch tip':
      command => "sed -i 's/^    def _is_livepatch_supported(self):\$/&\\n        return False/' ${dialogs}",
      onlyif  => "grep -Pzq 'def _is_livepatch_supported\\(self\\):\\n(?!        return False\\n)' ${dialogs}",
      path    => ['/usr/bin', '/bin'],
    }
  }
}
