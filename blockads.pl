#!/usr/bin/perl -w
use 5.010;
use strict;
use warnings;
# use Digest::MD5;
use Data::Dumper;

# subroutines section
sub single_replace {
    # $_[0] = what2replace, $_[1] = replace_with, $_[2] = input_string
    my ($target, $replacement, $input) = @_;
    $input =~ s/$target/$replacement/;    return $input;
    # my $str_input;    $str_input = $_[2];    $str_input =~ s/$_[0]/$_[1]/;    return $str_input;
}
sub file2array {    # $_[0] = file_location
    my @array;    open (my $current_file, "<", "$_[0]")
        or die("Exit'd, can't open $_[0] for reading: $!\n");
    @array = readline $current_file;    close $current_file;    return @array;
}
sub sayarray2file {    # $_[0] = file_location, @array
    my @output = @{$_[1]};
    open my $current_file, ">", "$_[0]"
        or die("Exit'd, can't open output $_[0] for writing: $!\n");
    for (my $i=0; $i<=$#output; $i++){ say $current_file $output[$i];}
    close $current_file;;    say "$_[0] updated."; return;
}
sub printarray2file {    # $_[0] = file_location, @array
    my @output = @{$_[1]};
    open my $current_file, ">", "$_[0]"
        or die("Exit'd, can't open output $_[0] for writing: $!\n");
    for (my $i=0; $i<=$#output; $i++){ print $current_file $output[$i];}
    close $current_file;;    say "$_[0] updated."; return;
}
sub uniqify { # use uniqify(\@array1); as input array..
    my ($ref_in_array) = @_;    my %seen = ();
    my @uniq = grep { ! $seen{ $_ }++ } @$ref_in_array;    return @uniq;
}
sub sayarray {     # eg sayarray(\@array)
    my ($ref_in_array) = @_; for (@$ref_in_array) { say $_; } return };
sub printarray {
    my ($ref_in_array) = @_; for (@$ref_in_array) { print $_; } return};
sub max ($$) { $_[$_[0] < $_[1]] };
sub min ($$) { $_[$_[0] > $_[1]] };
#############################################
################ demarcation ################
#############################################

# load static configurations
my @sources  = file2array('config/source_hosts');
my @includes = file2array('config/manual_includes');
my @excludes = file2array('config/manual_excludes');

# set up run conditions
my $prod  = 1;    # 1 for production, 0 for debug (more verbose)
my $fetch = 1;    # 0 to use cached files, 1 to download from sources
my $crazy = 0;    # 1 to include the massive host file from hosts-file.net

# clean up comments, etc.
if (! $prod) {
    # say "@includes", " ------------ counted lines : ", $#includes + 1;
    # @includes = clean(@includes);
    # say "@includes", " ------------ counted lines : ", $#includes + 1;
}
@sources  = clean(@sources);
@includes = clean(@includes);
@excludes = clean(@excludes);

if (! $prod) {
    sayarray2file('cache/source_hosts',    \@sources);
    sayarray2file('cache/manual_includes', \@includes);
    sayarray2file('cache/manual_excludes', \@excludes);
}

# assume wget is present, due to laziness
if ($fetch) {
    if ($^O eq 'linux'){
        my $zipped = 'http://hosts-file.net/download/hosts.zip';
        say "downloading $zipped";
        `wget -qP cache http://hosts-file.net/download/hosts.zip -O cache/hosts.zip`;
        say "unzipping cache/hosts.zip";
        `unzip -p cache/hosts.zip hosts.txt > cache/hosts.txt`
    }

    for (my $i = 0; $i < @sources; $i++) {
        my $cmd = "wget -q -O cache/$i.host " . $sources[$i];
        say "running $cmd";
        system $cmd;
    }
}

# assume x.host files exists in cache/
my $cdirty = 0; #@includes;
my $cclean = 0;
my @merged;
push @merged, @includes;        # includes at begin, excludes at end
foreach (glob('cache/*.host')) {
    my $file = $_;
    my @tmp = file2array($file);
    $cdirty += @tmp;
    print "$_ " . ($#tmp + 1);
    @tmp = clean(@tmp);
    $cclean += @tmp;
    print " -> " . ($#tmp + 1) . ($prod ? "\n" : ' ');
    push @merged, @tmp;
    if (! $prod) {
        $file =~ s/host/clean/;
        sayarray2file($file, \@tmp);
    }
}
if ($crazy) {
    # assume file exists due to laziness
    my $file = 'cache/hosts.txt';
    my @tmp = file2array($file);
    $cdirty += @tmp;
    print "$file " . ($#tmp + 1);
    @tmp = clean(@tmp);
    $cclean += @tmp;
    print " -> " . ($#tmp + 1) . ($prod ? "\n" : ' ');
    push @merged, @tmp;
    if (! $prod) {
        $file =~ s/txt/clean/;
        sayarray2file($file, \@tmp);
    }
}
printf("Stage(clean): $cdirty->$cclean %.2f%% reduction.\n", ($cdirty - $cclean) / $cdirty * 100);
@merged = uniqify(\@merged);
my $cmerge = @merged;
printf("Stage(quick merge): $cclean->$cmerge %.2f%% reduction.\n", ($cclean - $cmerge) / $cclean * 100);

sayarray2file('cache/merged_study', \@merged) if (! $prod);

my @xd;
my @rev_tld;
# my $cdots = 0;
for (my $i = 0; $i < @merged; $i++) {
    push @xd, [reverse split(/\./, $merged[$i])];
    push @rev_tld, rev($merged[$i]);;

    # my $cntdts = () = $merged[$i] =~ /\./g;  # $c is now 3
    # $cdots = max($cdots, $cntdts);

    # say "$cntdts " . $merged[$i] . " -> @expand -> " . join('.', reverse(@expand));   # print "$cntdts ";
    # say "--------------------------------------";
    # last if ($i == 1000);
}
# say 'max dots in between urls -> ' . $cdots;
# print Dumper \@rev_tld;

@rev_tld = map { s/-/\@/gr } @rev_tld;          # MUST BE REVERTED, due to sorting issue
@rev_tld = sort @rev_tld;
sayarray2file('cache/rev_tld_sorted', \@rev_tld) if (! $prod);

# pass 1, if seen on lower level automatic comment out the rest
my $prev_line = $rev_tld[0];
my $prev_cdot = () = $rev_tld[0] =~ /\./g;
for (my $i = 1; $i < @rev_tld; $i++) {
    my $curr_line = $rev_tld[$i];
    if ($curr_line =~ /$prev_line\./) {
        $rev_tld[$i] =~ s/^/# /;        # say "$curr_line";
    } else {
        $prev_line = $curr_line;
    }
}
sayarray2file('cache/rev_tld_sorted_pass1', \@rev_tld) if (! $prod);
@rev_tld = clean(@rev_tld);
my $cpass1 = @rev_tld;
sayarray2file('cache/rev_tld_sorted_pass1_clean', \@rev_tld) if (! $prod);
printf("Stage(pass 1): $cmerge->$cpass1 %.2f%% reduction.\n", ($cmerge - $cpass1) / $cmerge * 100);

### #############################################################################
### #### pass 2 introduce false positive, comment out for historical reason. ####
### #############################################################################
### # pass 2, find blocks of x to clean up further
### my %tld_l4;
### my %tld_l3;
### my %tld_l2;
### # my @tld_l1;
### for (my $i = 0; $i < @rev_tld; $i++) {
###     my $cdots = () = $rev_tld[$i] =~ /\./g;

###     # if ($cdots == 1) {
###     #   my $tredots = $rev_tld[$i];
###     #   $tredots =~ /^([^\.]+\.[^\.]+)/;
###     #   push @tld_l1, $1;
###     # }

###     # if ($cdots == 2) {
###     #   my $tredots = $rev_tld[$i];
###     #   $tredots =~ /^([^\.]+\.[^\.]+\.)/;
###     #   die("$1 from $tredots");
###     #   $tld_l2{$1} += 1;
###     # }

###     if ($cdots == 2) {
###         my $tredots = $rev_tld[$i];
###         $tredots =~ /^([^\.]+\.[^\.]+)\./;
###         $tld_l2{$1} += 1;
###     }

###     if ($cdots == 3) {
###         my $tredots = $rev_tld[$i];
###         $tredots =~ /^([^\.]+\.[^\.]+\.[^\.]+)\./;
###         $tld_l3{$1} += 1;
###     }

###     if ($cdots >= 4) {
###         my $tredots = $rev_tld[$i];
###         $tredots =~ /^([^\.]+\.[^\.]+\.[^\.]+\.[^\.]+)\./;
###         $tld_l4{$1} += 1;
###     }
### }

### # for (@tld_l1) {       # this is too slow
### #   my $l1dot = $_ . '.';
### #   @rev_tld = map { s/^$l1dot/# $l1dot/r } @rev_tld;
### #   last;
### # }
### # sayarray2file('cache/rev_tld_l1dot', \@rev_tld) if (! $prod);

### # print Dumper \%tld_l1;
### my @pass2replace;
### foreach my $name (reverse sort { $tld_l2{$a} <=> $tld_l2{$b} } keys %tld_l2) {
###      if ($tld_l2{$name} >= 64 and ! ($name =~ /\.co$|\.com$/)) {        # 64 to give a benefit of doubt
###         printf "tld_l2 %s:%s \n", $name, $tld_l2{$name};
###         push @pass2replace, $name;
###      };
### }
### foreach my $name (reverse sort { $tld_l3{$a} <=> $tld_l3{$b} } keys %tld_l3) {
###      if ($tld_l3{$name} >= 16) {        # 16 to give a benefit of doubt
###         printf "tld_l3 %s:%s \n", $name, $tld_l3{$name};
###         push @pass2replace, $name;
###      };
### }
### foreach my $name (reverse sort { $tld_l4{$a} <=> $tld_l4{$b} } keys %tld_l4) {
###     if ($tld_l4{$name} >= 4) {      # 16 to give a benefit of doubt
###         printf "tld_l4 %s:%s \n", $name, $tld_l4{$name};
###         push @pass2replace, $name;
###     }
### }
### # @pass2replace = sort @pass2replace;   # not needed anyway
### # print Dumper \@pass2replace;

### for (@pass2replace) {
###     my $tgt = $_;
###     # say "# $tgt";
###     @rev_tld = map { s/^$tgt/# $tgt/r } @rev_tld;
### }
### push @rev_tld, @pass2replace;

### sayarray2file('cache/rev_tld_sorted_pass2', \@rev_tld) if (! $prod);
### @rev_tld = clean(@rev_tld);
### @rev_tld = map { s/\@/-/gr } @rev_tld;  #revert for earlier workaround
### @rev_tld = sort @rev_tld;
### my $cpass2 = @rev_tld;
### sayarray2file('cache/rev_tld_sorted_pass2_clean', \@rev_tld) if (! $prod);
### printf("Stage(pass 2): $cpass1->$cpass2 %.2f%% reduction.\n", ($cpass1 - $cpass2) / $cpass1 * 100);

# excluding
for (@excludes) {
    my $find = rev($_);
    @rev_tld = map { s/^$find$//r } @rev_tld;
}
# print (($#rev_tld + 1) . ' ') ;
@rev_tld = grep { $_ ne '' } @rev_tld;
# print (($#rev_tld + 1) . ' ') ;
my $cend = @rev_tld;
sayarray2file('cache/rev_tld_sorted_pass2_clean_excludes', \@rev_tld) if (! $prod);
printf("Stage(end): $cdirty->$cend %.2f%% reduction.\n", ($cdirty - $cend) / $cdirty * 100);

# write to config
for (my $i = 0; $i < @rev_tld; $i++) {
    $rev_tld[$i] = 'zone "' . rev($rev_tld[$i]) . '" {type master;notify no;file "/etc/bind/db.empty";};';
}

@rev_tld = map { s/\@/-/gr } @rev_tld;          # reverting back from @ to -

if ($^O eq 'MSWin32'){
    sayarray2file('cache/named.conf.adblock', \@rev_tld);
} else {
    sayarray2file('cache/named.conf.adblock', \@rev_tld);
    if ($prod) {
        system "sudo cp cache/named.conf.adblock /etc/bind/";
        system "sudo /etc/init.d/bind9 restart";
    }
}

# application specific functions
sub clean {
    # dealing with hosts files, commented config files
    my @dirty = @_;
    my @clean;
    @clean = map { s/\s*#.*$//r } @dirty;                       # comments
    @clean = map { s/((127|0)\.0\.0\.(1|0))|::1//gr } @clean;   # loopback
    @clean = map { s/^\s*localhost\s*$//r } @clean;

    # @clean = map { s/\.$//r } @clean;        # end . is ng, not working with v5.14 in linux
    # $_ =~ s/\.$//; for \@clean;
    for (my $i = 0; $i < @clean; $i++) {    # workaround for perl 5.14
        if ($clean[$i] =~ /\.\s*$/) {
            # say "\nDAMMIT " . $clean[$i];
            $clean[$i] =~ s/\.\s*$//;
        }
    }

    @clean = map { s/^<*.+>$//r } @clean;                       # tag < .+ >

    @clean = map { s/(^\s+)|(^\s*$)|(\s+$)//gr } @clean;        # space
    @clean = grep { $_ ne '' } @clean;                          # blanks new lines

    $_ = lc for @clean;
    chomp(@clean);

    return @clean;
}
sub rev { return join '.', reverse split(/\./, $_[0]); }

