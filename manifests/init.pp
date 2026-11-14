# @summary Removes advertising from Ubuntu
#
# Implements the recommendations from https://github.com/Skyedra/UnspamifyUbuntu
#
# @param replace_ua_tools
#   Replace ubuntu-advantage-tools with the fake-ubuntu-advantage-tools stub
#   package, which removes the "Try Ubuntu Pro" APT messages. Also removes any
#   cached ESM announcement shown at login.
# @param disable_esm_hook
#   Remove the APT hook that tries to start apt-news.service and
#   esm-cache.service after ubuntu-advantage-tools is gone.
# @param disable_motd_news
#   Set ENABLED=0 in /etc/default/motd-news to stop dynamic MOTD ads.
#   Installs motd-news-config, which owns that file.
# @param patch_apt_check
#   Patch /usr/lib/update-notifier/apt_check.py so it no longer prints the
#   "ESM Apps is not enabled" messages at login. Opt-in, because it edits a
#   file owned by update-notifier-common.
# @param keep_distro_info
#   Install distro-info and mark it manually installed. ubuntu-advantage-tools
#   was the only package depending on it, so apt would otherwise offer to
#   autoremove it.
#
# @example
#   include unspamify
#
class unspamify (
  Boolean $replace_ua_tools  = true,
  Boolean $disable_esm_hook  = true,
  Boolean $disable_motd_news = true,
  Boolean $patch_apt_check   = false,
  Boolean $keep_distro_info  = false,
) {
  if $facts['os']['name'] != 'Ubuntu' {
    fail("${module_name} only supports Ubuntu, not ${facts['os']['name']}")
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

    exec { 'regenerate motd updates-available':
      command     => '/usr/lib/update-notifier/update-motd-updates-available --force',
      refreshonly => true,
    }
  }
}
