#!/usr/bin/env perl

use 5.012;
use utf8;
use Data::Dumper;
use JSON;

=api
https://api.github.com/repos/embedded2013/rtenv/forks
https://api.github.com/repos/embedded2013/rtenv/commits
=cut

sub api_call {
    my $api = shift;
    my $json = `wget https://api.github.com/$api -O - 2>/dev/null`;
    from_json($json);
}


sub get_fork_repo {
    my $json = api_call("repos/embedded2013/rtenv/forks");
    my @forks = ();
    for (@$json) {
        push @forks, $_->{full_name};
    }
    @forks;
}

my $json = api_call("repos/tim37021/rtenv/commits");
for (@$json) {
    say $_->{sha};
    say $_->{commit}{message};
    say "------";
}
