# frozen_string_literal: true

require 'spec_helper'

describe 'unspamify' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with defaults' do
        it { is_expected.to compile.with_all_deps }

        it { is_expected.to contain_file('/var/cache/unspamify').with_ensure('directory') }

        it do
          is_expected.to contain_file('/var/cache/unspamify/fake-ubuntu-advantage-tools.deb')
            .with_source('puppet:///modules/unspamify/fake-ubuntu-advantage-tools.deb')
        end

        it do
          is_expected.to contain_exec('install fake-ubuntu-advantage-tools')
            .with_command('apt-get install -y /var/cache/unspamify/fake-ubuntu-advantage-tools.deb')
            .that_requires('File[/var/cache/unspamify/fake-ubuntu-advantage-tools.deb]')
        end

        it do
          is_expected.to contain_file('/var/lib/ubuntu-advantage/messages/motd-esm-announce')
            .with_ensure('absent')
            .that_requires('Exec[install fake-ubuntu-advantage-tools]')
        end

        it do
          is_expected.to contain_exec('purge ubuntu-advantage-tools')
            .with_command(
              "dpkg-query -W -f='${db:Status-Abbrev} ${Package}\\n' " \
              'ubuntu-advantage-tools ubuntu-pro-client ubuntu-advantage-desktop-daemon ' \
              "2>/dev/null | awk '$1 == \"rc\" { print $2 }' | xargs -r dpkg --purge",
            )
            .with_onlyif(%r{awk '\$1 == "rc" \{ print \$2 \}' \| grep -q \.\z})
            .that_requires('Exec[install fake-ubuntu-advantage-tools]')
        end

        it { is_expected.to contain_file('/etc/apt/apt.conf.d/20apt-esm-hook.conf').with_ensure('absent') }
        it { is_expected.to contain_package('motd-news-config') }

        it do
          is_expected.to contain_file_line('disable motd-news')
            .with_path('/etc/default/motd-news')
            .with_line('ENABLED=0')
            .that_requires('Package[motd-news-config]')
        end

        it { is_expected.to contain_file('/var/lib/update-notifier').with_ensure('directory') }

        it do
          is_expected.to contain_file('/var/lib/update-notifier/hide-esm-in-motd')
            .with_ensure('file')
            .that_notifies('Exec[regenerate motd updates-available]')
        end

        it do
          is_expected.to contain_exec('regenerate motd updates-available')
            .with_command('/usr/lib/update-notifier/update-motd-updates-available --force')
            .with_onlyif('test -x /usr/lib/update-notifier/update-motd-updates-available')
            .with_refreshonly(true)
        end

        it { is_expected.not_to contain_package('distro-info') }
        it { is_expected.not_to contain_exec('mark distro-info manual') }
        it { is_expected.not_to contain_exec('patch apt_check.py ESM messages') }
        it { is_expected.not_to contain_exec('patch Dialogs.py Livepatch tip') }
        it { is_expected.not_to contain_exec('disable apt_news') }
      end

      context 'with replace_ua_tools => false' do
        let(:params) { { replace_ua_tools: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/var/cache/unspamify') }
        it { is_expected.not_to contain_file('/var/cache/unspamify/fake-ubuntu-advantage-tools.deb') }
        it { is_expected.not_to contain_exec('install fake-ubuntu-advantage-tools') }
        it { is_expected.not_to contain_file('/var/lib/ubuntu-advantage/messages/motd-esm-announce') }
        it { is_expected.not_to contain_exec('purge ubuntu-advantage-tools') }
      end

      context 'with purge_ua_tools => false' do
        let(:params) { { purge_ua_tools: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_exec('purge ubuntu-advantage-tools') }
      end

      context 'with replace_ua_tools => false and disable_apt_news => true' do
        let(:params) { { replace_ua_tools: false, disable_apt_news: true } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_exec('disable apt_news')
            .with_command('pro config set apt_news=false')
            .with_unless("pro config show apt_news | grep -qx 'apt_news False'")
        end
      end

      context 'with disable_apt_news => true' do
        let(:params) { { disable_apt_news: true } }

        it { is_expected.to compile.and_raise_error(%r{disable_apt_news needs the real Pro client}) }
      end

      context 'with hide_esm_motd => false' do
        let(:params) { { hide_esm_motd: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/var/lib/update-notifier') }
        it { is_expected.not_to contain_file('/var/lib/update-notifier/hide-esm-in-motd') }
        it { is_expected.not_to contain_exec('regenerate motd updates-available') }
      end

      context 'with disable_esm_hook => false' do
        let(:params) { { disable_esm_hook: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/etc/apt/apt.conf.d/20apt-esm-hook.conf') }
      end

      context 'with disable_motd_news => false' do
        let(:params) { { disable_motd_news: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('motd-news-config') }
        it { is_expected.not_to contain_file_line('disable motd-news') }
      end

      context 'with keep_distro_info => true' do
        let(:params) { { keep_distro_info: true } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('distro-info').with_ensure('installed') }

        it do
          is_expected.to contain_exec('mark distro-info manual')
            .with_command('apt-mark manual distro-info')
            .with_unless('apt-mark showmanual distro-info | grep -qx distro-info')
            .that_requires('Package[distro-info]')
        end
      end

      context 'with hide_esm_motd => false and patch_apt_check => true' do
        let(:params) { { hide_esm_motd: false, patch_apt_check: true } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_exec('patch apt_check.py ESM messages')
            .with_command(%r{sed -Ezi\.orig .* /usr/lib/update-notifier/apt_check\.py}m)
            .with_onlyif(%r{grep -Pzq .* /usr/lib/update-notifier/apt_check\.py})
            .that_notifies('Exec[regenerate motd updates-available]')
        end

        it do
          is_expected.to contain_exec('regenerate motd updates-available')
            .with_command('/usr/lib/update-notifier/update-motd-updates-available --force')
            .with_refreshonly(true)
        end
      end

      context 'with patch_livepatch_tip => true' do
        let(:params) { { patch_livepatch_tip: true } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_exec('patch Dialogs.py Livepatch tip')
            .with_command(
              "sed -i 's/^    def _is_livepatch_supported(self):$/&\\n        return False/' " \
              '/usr/lib/python3/dist-packages/UpdateManager/Dialogs.py',
            )
            .with_onlyif(
              "grep -Pzq 'def _is_livepatch_supported\\(self\\):\\n(?!        return False\\n)' " \
              '/usr/lib/python3/dist-packages/UpdateManager/Dialogs.py',
            )
        end
      end
    end
  end

  context 'on a non-Ubuntu OS' do
    let(:facts) { { os: { 'name' => 'Debian', 'family' => 'Debian' } } }

    it { is_expected.to compile.and_raise_error(%r{unspamify only supports Ubuntu, not Debian}) }
  end
end
