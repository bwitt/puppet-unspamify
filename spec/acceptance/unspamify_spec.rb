# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'unspamify' do
  # Container images don't ship the Pro client; install it so the swap is real
  before(:all) do
    shell('apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ubuntu-pro-client')
  end

  context 'with keep_distro_info => true' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) { 'class { "unspamify": keep_distro_info => true }' }
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

    describe command('apt-mark showmanual distro-info') do
      its(:stdout) { is_expected.to match(%r{^distro-info$}) }
    end

    describe file('/etc/apt/apt.conf.d/20apt-esm-hook.conf') do
      it { is_expected.not_to exist }
    end

    describe file('/etc/default/motd-news') do
      its(:content) { is_expected.to match(%r{^ENABLED=0$}) }
    end
  end
end
