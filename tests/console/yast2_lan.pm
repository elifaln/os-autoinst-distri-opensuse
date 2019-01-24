# SUSE's openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.


# Summary: yast2 lan functionality test https://bugzilla.novell.com/show_bug.cgi?id=600576
# Maintainer: Jozef Pupava <jpupava@suse.com>

use base "console_yasttest";
use strict;
use testapi;
use utils;
use y2lan_restart_common;
use version_utils ':VERSION';
use utils 'zypper_call';

sub handle_Networkmanager_controlled {
    send_key "ret";    # confirm networkmanager popup
    assert_screen "Networkmanager_controlled-approved";
    send_key "alt-c";
    if (check_screen('yast2-lan-really', 3)) {
        # SLED11...
        send_key 'alt-y';
    }
    wait_serial("yast2-lan-status-0", 60) || die "'yast2 lan' didn't finish";
}

sub handle_dhcp_popup {
    if (match_has_tag('dhcp-popup')) {
        wait_screen_change { send_key 'alt-o' };
    }
}


sub set_network {
    my (%args) = @_;
    my ($loop, $param) = @_;
    script_run("yast2 lan; echo yast2-lan-status-\$? > /dev/$serialdev", 0);
    assert_screen "yast2_lan";
    send_key 'alt-i';    # edit NIC
    assert_screen 'yast_ncurses_network_card_setup';
    if ($args{static}) {
        send_key 'alt-t';    # set to static ip
        assert_screen 'yast_ncurses_set_static_ip';
        send_key 'tab';
        if ($args{ip}) {     # To spare time, no update what to is already filled from previous run
            send_key_until_needlematch('NICsetup_ncurses_IP_empty', 'backspace');    # delete existing IP if any
            type_string $args{ip};
        }
        send_key 'tab';
        if ($args{mask}) {                                                           # To spare time, no update what to is already filled from previous run
            send_key_until_needlematch('NICsetup_ncurses_mask_empty', 'backspace');    # delete existing netmask if any
            type_string $args{mask};
        }
        send_key 'tab';
        send_key_until_needlematch('NICsetup_ncurses_host_empty', 'backspace');
        type_string $args{fqdn};
        assert_screen 'yast_ncurses_static_ip_set';
    }
    else {
        send_key 'alt-y';                                                              # set back to DHCP
        assert_screen 'yast_ncurses_set_dhcp';
    }
    # Exit
    send_key 'alt-n';
    assert_screen "yast2_lan";
    send_key 'alt-o';
    wait_serial("yast2-lan-status-0", 180) || die "'yast2 lan' didn't finish";
}


sub check_etc_hosts_update {

=head2

In order to targer bugs bsc#1115644 and bsc#1052042, we want to :
- Set static IP and fqdn for first NIC in the list and check /etc/hosts formatting
- Open yast2 lan again and change the fqdn, check if /etc/hosts is changed correctly ( bsc#1052042 )
- Set it to DHCP
- Set it again to static with  new FQDN and check if /etc/hosts is changed correctly ( bsc#1115644 )

=cut

    my $looprun = 1;
    my $hostname;
    my $fqdn;
    my $ip = '192.168.122.10';
    script_run "cat /etc/hosts";
    until ($looprun == 4) {
        $hostname = "tst-$looprun";
        $fqdn     = $hostname . '.com';
        set_network(static => 1, fqdn => $fqdn, ip => $ip, mask => '/24');
        script_run("egrep \"$ip\\s$fqdn\\s$hostname\" /etc/hosts", 30)
          && record_soft_failure "bsc#1115644 Expected entry : \"192.168.1.10    $fqdn $hostname\" was not found in /etc/hosts";
        if ($looprun == 2) {
            set_network(fqdn => $fqdn);    # Without parameter, set as dhcp, step is necessary to make sure
        }
        script_run "cat /etc/hosts";
        $looprun++;
    }
    set_network;
}


sub run {
    my $self = shift;

    select_console 'root-console';
    zypper_call "in yast2-network";    # make sure yast2 lan module installed

    # those two are for debugging purposes only
    script_run('ip a');
    script_run('ls -alF /etc/sysconfig/network/');
    save_screenshot;

    script_run("yast2 lan; echo yast2-lan-status-\$? > /dev/$serialdev", 0);

    assert_screen [qw(Networkmanager_controlled yast2_lan install-susefirewall2 install-firewalld dhcp-popup)], 120;
    handle_dhcp_popup;
    if (match_has_tag('Networkmanager_controlled')) {
        handle_Networkmanager_controlled;
        return;    # don't change any settings
    }
    if (match_has_tag('install-susefirewall2') || match_has_tag('install-firewalld')) {
        # install firewall
        send_key "alt-i";
        # check yast2_lan again after firewall is installed
        assert_screen [qw(Networkmanager_controlled yast2_lan)], 90;
        if (match_has_tag('Networkmanager_controlled')) {
            handle_Networkmanager_controlled;
            return;
        }
    }

    my $hostname = get_var('HOSTNAME', 'susetest');
    my $domain   = "zq1.de";

    send_key "alt-s";    # open hostname tab
    assert_screen [qw(yast2_lan-hostname-tab dhcp-popup)];
    handle_dhcp_popup;
    send_key "tab";
    for (1 .. 15) { send_key "backspace" }
    type_string $hostname;
    # Starting from SLE 15 SP1, we don't have domain field
    if (is_sle('<=15') || is_leap('<=15.0')) {
        send_key "tab";
        for (1 .. 15) { send_key "backspace" }
        type_string $domain;
    }
    assert_screen 'test-yast2_lan-1';

    send_key "alt-o";    # OK=>Save&Exit
    wait_serial("yast2-lan-status-0", 180) || die "'yast2 lan' didn't finish";
    wait_still_screen;

    # Run detailed check only if explicitly configured in the test suite
    check_etc_hosts_update() if get_var('VALIDATE_ETC_HOSTS');

    $self->clear_and_verify_console;
    assert_script_run "hostname|grep $hostname";

    clear_console;
    script_run('ip -o a s');
    script_run('ip r s');
    assert_script_run('getent ahosts ' . get_var("OPENQA_HOSTNAME"));
}


sub test_flags {
    return {always_rollback => 1};    # Should only affect backends that have snapshot feature
}

1;
