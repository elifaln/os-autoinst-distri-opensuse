# Evolution tests
#
# Copyright © 2016 SUSE LLC

# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Test Case #1503976 Pop Meeting

use base "x11regressiontest";
use strict;
use warnings;
use testapi;
use utils;
use POSIX qw(strftime);

sub run() {
    my $self         = shift;
    my $mail_subject = $self->get_dated_random_string(4);
    #Setup account account A, and use it to send a meeting
    #send meet request by account A
    $self->setup_pop("internal_account_A");
    $self->send_meeting_request("internal_account_A", "internal_account_B", $mail_subject);
    assert_screen "evolution_mail-ready", 60;
    # Exit
    send_key "alt-f";
    send_key "q";
    wait_idle;

    #login with account B and check meeting request.
    $self->setup_pop("internal_account_B");
    $self->check_new_mail_evolution($mail_subject, "internal_account_B", "POP");
    wait_idle;
    # Exit
    send_key "ctrl-q";
}

1;
# vim: set sw=5 set:
