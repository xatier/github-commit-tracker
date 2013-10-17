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

open PG, ">", "page1.html";

say PG <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<link rel="stylesheet" href="http://netdna.bootstrapcdn.com/bootstrap/3.0.0-wip/css/bootstrap.min.css">
<script type="text/javascript" src="http://cdnjs.cloudflare.com/ajax/libs/jquery/2.0.3/jquery.min.js"></script>
<script type="text/javascript" src="http://cdnjs.cloudflare.com/ajax/libs/jquery.tablesorter/2.10.8/jquery.tablesorter.min.js"></script>

<script>
\$(document).ready(function()
    {
        \$("#myTable").tablesorter();
    }
);

</script>
</head>
<body>
<div class="container">
      <h1 id="">xatier's github commit log reporter</h1>

<table id="myTable" class="table table-striped table-bordered tablesorter">
<thead>
<tr>
    <th>repo</th>


END

# timestamp
my $last_ts = (api_call("repos/embedded2013/rtenv/stats/code_frequency"))->[-1][0];

for (reverse 0..4) {
    say PG "<th> " . scalar localtime ($last_ts - 604800*$_) . "</th>";
}

say PG <<END;
</tr>
</thead>
<tbody>
END

exit 0;

print "getting fork repo list...";
my @forks = get_fork_repo();
say "done.\n" . scalar @forks . " repos:";
say join "\n", @forks;

for my $repo (@forks) {
    my @count = get_weekly_commit_count($repo);
    my $count = $count[-1];
    printf "%35s", "$repo : $count / ";
    say join " ", @count;

    # sleep 0.5 sec
    select undef, undef, undef, 0.5;
}

say "</tbody></table> </div></body></html>";
