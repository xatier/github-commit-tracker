#!/usr/bin/env perl

use 5.012;
use utf8;
use Data::Dumper;
use JSON;
use Time::Piece;

# put OAuth key into key.pm
use key;
=key.pm

key.pm should be like this:

package key;
# https://github.com/settings/applications
# Personal Access Tokens
our $oauth_key = "";

=cut

#my $origin = "embedded2013/rtenv";
#my $origin = "embedded2013/freertos";
my $origin = "embedded2014/rtenv";
my $repo_dir = "rtenv";

my $create_time = (get_git_log($origin))[0][1];

my $lcltime = localtime;
my $week_count_max = 0;
for (1..1000000) {
    $week_count_max++;
    last if (($lcltime - $_*604800)->datetime lt $create_time);
}

say "in $week_count_max weeks since $create_time";
report_gen($origin);

# api call helper
sub api_call {
    my $api = shift;
    #say "calling https://api.github.com/$api";
    my $ret;

 retry:
    select undef, undef, undef, 0.1;   # sleep a while before calling some APIs
    eval {
        $ret = from_json(`wget https://api.github.com/$api?per_page=100 --header \"Authorization: token $key::oauth_key\" -O - 2>/dev/null`);
    };
    if ($@) {       # catch errors :(
        say "API call error!, sleep one second!";
        say ">>>    $@";
        sleep 1;
        goto retry;
    }
    if (ref $ret eq "HASH" && not %$ret) {
        say "get empty hash!";
        sleep 1;
        goto retry;
    }
    $ret;
}


# all repos forked from $origin
sub get_fork_repo {
    my $json = api_call("repos/$origin/forks");
    my @forks = ();
    for (@$json) {
        push @forks, $_->{full_name};
    }

# BFS all repos forked from the original one
again:
    my @append = ();
    for (@forks) {
        say "BFS on $_";
        $json = api_call("repos/$_/forks");
        for (@$json) {
            if (not $_->{full_name} ~~ @forks) {
                push @append, $_->{full_name};
            }
        }
    }

    say "found " . scalar @append . " more repos";

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
retry:
    my $json = api_call("repos/$repo/stats/participation");
    my @count = ();
    for (@{ $json->{all} }) {
        push @count, $_;
    }
    if (not defined $count[0]) {
        #can't get commit count, sleep
        say "can't get commit count, sleep one second!";
        sleep 1;
        goto retry;

    }
    @count[-($week_count_max+1) .. -1];
}

sub report_gen {
    my $origin = shift;
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

    for (reverse 0..$week_count_max) {
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

        reviewer($repo);

        my @count = get_weekly_commit_count($repo);

        # if something get error, f*cking github apis!
        # XXX: shouldn't happend now
        if (not defined $count[0]) {
            # can't get commit count, sleep
            say "X: can't get commit count, sleep one second!";
            #sleep 1;
            #redo;
        }

        printf "%35s", "$repo / ";
        say join " ", @count;

        push @td, [$repo, @count];

        # sleep 0.5 sec
        select undef, undef, undef, 1;
    }


    # sort the commit report according to the latest logs
    @td = sort {$b->[-1] <=> $a->[-1] or
                $b->[-2] <=> $a->[-2] or
                $b->[-3] <=> $a->[-3] or
                $b->[-4] <=> $a->[-4] or
                $b->[-5] <=> $a->[-5] or
                $b->[0] cmp $a-[0]
    } @td;


    for my $repo (@td) {
        # link to reviewer pagename: owner-repo.html
        (my $page_name = $repo->[0]) =~ s/\//-/;
        $page_name .= ".html";

        print PG "<tr><td><a href=\"https://github.com/$repo->[0]\" target=\"_blank\">";
        print PG "$repo->[0]</a> ->  ";
        print PG "<a href=\"http://cs5566.nctucs.net/$repo_dir/$page_name\" target=\"_blank\">review</a></td>";
        print PG "<td>$repo->[$_]</td>" for (1..($week_count_max+1));
        say PG "</tr>";

    }

    say PG "</tbody></table> </div></body></html>";

    close PG;

}


sub reviewer {
    my $repo = shift;
    # create pagename: owner-repo.html
    (my $page_name = $repo) =~ s/\//-/;
    open PG_, ">", "$page_name.html";

    say "generating reviewer of $repo ...";
    sleep 1;
    my $json = api_call("repos/$repo/comments");


    say PG_ <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<link rel="stylesheet" href="http://netdna.bootstrapcdn.com/bootstrap/3.0.0-wip/css/bootstrap.min.css">
<script type="text/javascript" src="http://cdnjs.cloudflare.com/ajax/libs/jquery/2.0.3/jquery.min.js"></script>
</head>
<body>
<div class="container">
      <h1 id="">xatier's github commit comments reviewer</h1>
      <h3>Original repo:
      <a href=\"https://github.com/$repo\" target=\"_blank\">$repo</a>
      </h3>

      <hr>
END

    # reserve order is better for reviewing I think
    for (reverse @$json) {
        say PG_ <<END;
    <p>
      <h3>$_->{user}{login} @
        <a href=\"$_->{html_url}\" target=\"_blank\"> $_->{updated_at}</a>
      </h3>
      <pre>$_->{body}</pre>
    </p>
    <hr>
END
    }
    say PG_ "</body></html>";

    close PG_;
}
