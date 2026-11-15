# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'unspamify' do
  # Container images don't ship these; install them so the changes are real
  before(:all) do
    shell('apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ' \
          'ubuntu-pro-client update-notifier-common update-manager')
  end

  # Runs first, while the real Pro client is still installed
  context 'with replace_ua_tools => false and disable_apt_news => true' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { 'class { "unspamify": replace_ua_tools => false, disable_apt_news => true }' }
    end

    describe package('ubuntu-pro-client') do
      it { is_expected.to be_installed }
    end

    describe command('pro config show apt_news') do
      its(:stdout) { is_expected.to match(%r{^apt_news False$}) }
    end
  end

  context 'with keep_distro_info => true and patch_livepatch_tip => true' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { 'class { "unspamify": keep_distro_info => true, patch_livepatch_tip => true }' }
    end

    %w[fake-ubuntu-advantage-tools distro-info].each do |pkg|
      describe package(pkg) do
        it { is_expected.to be_installed }
      end
    end

    %w[ubuntu-pro-client ubuntu-advantage-tools].each do |pkg|
      describe package(pkg) do
        it { is_expected.not_to be_installed }
      end
    end

    # Purged, not just removed
    describe command("dpkg-query -W -f='${db:Status-Abbrev}\\n' ubuntu-pro-client") do
      its(:stdout) { is_expected.not_to match(%r{^rc}) }
    end

    %w[/var/lib/ubuntu-advantage /etc/ubuntu-advantage/uaclient.conf].each do |path|
      describe file(path) do
        it { is_expected.not_to exist }
      end
    end

    describe command('apt-mark showmanual distro-info') do
      its(:stdout) { is_expected.to match(%r{^distro-info$}) }
    end

    describe file('/etc/apt/apt.conf.d/20apt-esm-hook.conf') do
      it { is_expected.not_to exist }
    end

    describe file('/etc/default/motd-news') do
      its(:content) { is_expected.to match(%r{^ENABLED=0$}) }
    end

    describe file('/var/lib/update-notifier/hide-esm-in-motd') do
      it { is_expected.to be_file }
    end

    describe file('/usr/lib/python3/dist-packages/UpdateManager/Dialogs.py') do
      its(:content) { is_expected.to match(%r{^    def _is_livepatch_supported\(self\):\n        return False\n}) }
    end
  end
end
