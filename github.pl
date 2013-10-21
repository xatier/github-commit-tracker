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

my $origin = "embedded2013/rtenv";
#my $origin = "embedded2013/freertos";


# api call helper
sub api_call {
    my $api = shift;
    #say "calling https://api.github.com/$api";
    from_json(`wget https://api.github.com/$api?per_page=100 --header \"Authorization: token $key::oauth_key\" -O - 2>/dev/null`);
}


# all repos forked from $origin
sub get_fork_repo {
    my $json = api_call("repos/$origin/forks");
    my @forks = ();
    for (@$json) {
        push @forks, $_->{full_name};
    }

# DFS all repos forked from the original one
again:
    my @append = ();
    for (@forks) {
        $json = api_call("repos/$_/forks");
        for (@$json) {
            if (not $_->{full_name} ~~ @forks) {
                push @append, $_->{full_name};
            }
        }
    }

    if (@append > 0) {
        push @forks, @append;
        goto again;
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
    @count[-5 .. -1];
}


# create pagename: owner-repo.html
(my $page_name = $origin) =~ s/\//-/;
open PG, ">", "$page_name.html";


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
      <h1 id="">xatier's github commit ranking reporter</h1>
      <h2>Original repo:
      <a href=\"https://github.com/$origin\" target=\"_blank\">$origin</a>
      </h2>

      <hr>

<table id="myTable" class="table table-striped table-bordered tablesorter">
<thead>
<tr>
    <th>repo</th>
END

# timestamp
my $last_ts = (api_call("repos/$origin/stats/code_frequency"))->[-1][0];

for (reverse 0..4) {
    say PG "<th> " . scalar localtime ($last_ts - 604800*$_) . "</th>";
}

say PG <<END;
</tr>
</thead>
<tbody>
END


# get 'fork from forked repos'
print "getting fork repo list...";
my @forks = get_fork_repo();
say "done.\n" . scalar @forks . " repos:";
say join "\n", @forks;



my @td = ();

# get commit count here
for my $repo (@forks) {
    my @count = get_weekly_commit_count($repo);

    # if something get error, f*cking github apis!
    if (not defined $count[3]) {
        # can't get commit count, sleep
        say "can't get commit count, sleep one second!";
        sleep 1;
        redo;
    }

    printf "%35s", "$repo / ";
    say join " ", @count;

    push @td, [$repo, @count];

    # sleep 0.5 sec
    select undef, undef, undef, 0.5;
}


# sort the commit report according to the latest logs
@td = sort {$b->[5] <=> $a->[5] or
            $b->[4] <=> $a->[4] or
            $b->[3] <=> $a->[3] or
            $b->[2] <=> $a->[2] or
            $b->[1] <=> $a->[1] or
            $b->[0] cmp $a-[0]
} @td;


for my $repo (@td) {

    print PG "<tr><td><a href=\"https://github.com/$repo->[0]\" target=\"_blank\">";
    print PG "$repo->[0]</a></td>";
    print PG "<td>$repo->[$_]</td>" for (1..5);
    say PG "</tr>";

}

say PG "</tbody></table> </div></body></html>";
