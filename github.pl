#!/usr/bin/env perl

use 5.012;
use utf8;
use Data::Dumper;
use JSON;

# put OAuth key into key.pm
use key;
=key.pm

key.pm should be like this:

package key;
# https://github.com/settings/applications
# Personal Access Tokens
our $oauth_key = "";

=cut


# api call helper
sub api_call {
    my $api = shift;
    #say "calling https://api.github.com/$api";
    from_json(`wget https://api.github.com/$api?per_page=100 --header \"Authorization: token $key::oauth_key\" -O - 2>/dev/null`);
}


# all repos forked from embedded2013/rtenv
sub get_fork_repo {
    my $json = api_call("repos/embedded2013/rtenv/forks");
    my @forks = ();
    for (@$json) {
        push @forks, $_->{full_name};
    }
    @forks;
}

# commit log
sub get_git_log {
    my $repo = shift;
    my $json = api_call("repos/$repo/commits");
    my @log = ();
    for (@$json) {
        push @log, [$_->{sha},
                    $_->{commit}{committer}{date},
                    $_->{commit}{message}];
    }
    @log;
}


# weekly additions and deletions
sub get_code_freqency {
    my $repo = shift;
    my $json = api_call("repos/$repo/stats/code_frequency");
    my @freq = ();
    for (@$json) {
        push @freq, [scalar localtime $_->[0],
                     $_->[1],
                     $_->[2]];
    }
    @freq;
}

sub get_weekly_commit_count {
    my $repo = shift;
    my $json = api_call("repos/$repo/stats/participation");
    my @count = ();
    for (@{ $json->{all} }) {
        push @count, $_;
    }
    #@count = ;
    @count[-10 .. -1];
}


=tests
my @tim_s_log = get_git_log("tim37021/rtenv");
for (@tim_s_log) {
    say $_->[0];
    say $_->[1];
    say $_->[2];
    say "------"x3;
}
for (get_code_freqency("xatier/cs_note")) {
    say $_->[0];
}
get_weekly_commit_count("tim37021/rtenv");
=cut

print "getting fork repo list...";
my @forks = get_fork_repo();
say "done.\n" . scalar @forks . " repos:";
say join "\n", @forks;

for my $repo (@forks) {
    my @count = get_weekly_commit_count($repo);
    my $count = $count[-1];
    printf "%35s", "$repo : $count / ";
    say join " ", @count;

    # sleep 0.25 sec
    select undef, undef, undef, 0.25;
}
