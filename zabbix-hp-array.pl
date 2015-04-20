#!/usr/bin/perl

# reqire Parse::HP::ACU from cpan or for debian it can be downloaded from https://znik.sk/deb/pool/ (see https://github.com/petzah/libparse-hp-acu-perl)
# require sudo or root access (for hpacucli binary) or it can read from file

use strict;
use Parse::HP::ACU;
use Data::Dumper;
use Switch;
use JSON;
use File::Path qw( make_path );

# config
my $cachefile = ".hpacu";
my $hpacuclioutputfile = "hpacucli.out"; # get this file from cron or so with "hpacucli controller all show config detail > hpacucli.out"
my $tmpdir = "/tmp/zabbix-hp-array";
my $cacheexpire = 60; # seconds
my $hpfile = "$tmpdir/$hpacuclioutputfile";
my $file = "$tmpdir/$cachefile";

# hash reference for controllers
my $controllers;

make_path ($tmpdir);
write_cache_file($file, $controllers = parse()) if (! -e $file);

# if cache file is older than $cacheexpire then write new data to cachefile
my $mtimestamp = (stat($file))[9];
if ((time - $mtimestamp) > $cacheexpire) {
    write_cache_file($file, $controllers = parse());
}

# get controllers from cache file
$controllers = eval { do $file };

sub parse {
    my $acu = Parse::HP::ACU->new();
    my $controllers = $acu->parse_config_file($hpfile); # from file
#    my $controllers = $acu->parse_config(); # from output of hpacucli command (req root)
    return $controllers;
}

sub write_cache_file {
    my ($file,$controllers) = @_;
    open(FILE, ">$file") || die "Can not open: $!";
    print FILE Data::Dumper->Dump([$controllers],["controllers"]);
    close(FILE) || die "Error closing file: $!";
}

sub controller_discovery {
    my @out;
    foreach my $key (keys %$controllers) {
        push(@out, {
                '{#HPACUCTRLID}'=>$key,
                '{#HPACUCTRLSN}'=>$controllers->{$key}->{'serial_number'}
        });
    }

    print encode_json({'data'=>\@out});
}

sub array_discovery {
    my @out;
    foreach my $controllerid (keys %$controllers) {
        foreach my $arrayid (keys $controllers->{$controllerid}->{'array'}) {
            push(@out, {
                '{#HPACUCTRLID}'=>$controllerid,
                '{#HPACUARRID}'=> $arrayid
            });
        }
    }
    print encode_json({'data'=>\@out});
}

sub logicaldrive_discovery {
    my @out;
    foreach my $controllerid (keys %$controllers) {
        foreach my $arrayid (keys $controllers->{$controllerid}->{'array'}) {
            foreach my $logicaldriveid (keys $controllers->{$controllerid}->{'array'}->{$arrayid}->{'logical_drive'}) {
                push(@out, {
                    '{#HPACULOGID}'=>$logicaldriveid,
                    '{#HPACULOGUN}'=>$controllers->{$controllerid}->{'array'}->{$arrayid}->{'logical_drive'}->{$logicaldriveid}->{'unique_identifier'},
                    '{#HPACUCTRLID}'=>$controllerid,
                    '{#HPACUARRID}'=> $arrayid
                });
            }
        }
    }
    print encode_json({'data'=>\@out});
}

sub physicaldrive_discovery {
    my @out;
    foreach my $controllerid (keys %$controllers) {
        foreach my $arrayid (keys $controllers->{$controllerid}->{'array'}) {
            foreach my $physicaldriveid (keys $controllers->{$controllerid}->{'array'}->{$arrayid}->{'physical_drive'}) {
                push(@out, {
                    '{#HPACUPHYID}'=>$physicaldriveid,
                    '{#HPACUPHYSN}'=>$controllers->{$controllerid}->{'array'}->{$arrayid}->{'physical_drive'}->{$physicaldriveid}->{'serial_number'},
                    '{#HPACUCTRLID}'=>$controllerid,
                    '{#HPACUARRID}'=>$arrayid
                });
            }
        }
    }
    print encode_json({'data'=>\@out});
}

sub controller_item {
    my ($controllerid, $item) = @_;
    print $controllers->{$controllerid}->{$item};
}

sub array_item {
    my ($controllerid, $arrayid, $item) = @_;
    print $controllers->{$controllerid}->{'array'}->{$arrayid}->{$item} if defined $controllers->{$controllerid}->{'array'}->{$arrayid}->{$item} ;
}

sub logicaldrive_item {
    my ($controllerid, $log, $item) = @_;
    
    # search for logical drive
    foreach my $arrayid (keys $controllers->{$controllerid}->{'array'}) {
        foreach my $logicaldriveid (keys $controllers->{$controllerid}->{'array'}->{$arrayid}->{'logical_drive'}) {
            if ($log eq $logicaldriveid) {
                print $controllers->{$controllerid}->{'array'}->{$arrayid}->{'logical_drive'}->{$logicaldriveid}->{$item};
            }
        }
    }
}

sub physicaldrive_item {
    my ($controllerid, $arrayid, $phy, $item) = @_;
    
    # search for physical drive
    foreach my $physicaldriveid (keys $controllers->{$controllerid}->{'array'}->{$arrayid}->{'physical_drive'}) {
        if ($phy eq $physicaldriveid) {
            print $controllers->{$controllerid}->{'array'}->{$arrayid}->{'physical_drive'}->{$physicaldriveid}->{$item};
        }
    }
}

switch ($ARGV[0]) {
    case "controller_discovery" { controller_discovery(); }
    case "array_discovery" { array_discovery(); }
    case "logicaldrive_discovery" { logicaldrive_discovery(); }
    case "physicaldrive_discovery" { physicaldrive_discovery(); }

    case "controller_item" { controller_item($ARGV[1], $ARGV[2]); }
    case "array_item" { array_item($ARGV[1], $ARGV[2], $ARGV[3]); }
    case "logicaldrive_item" { logicaldrive_item($ARGV[1], $ARGV[2], $ARGV[3]); }
    case "physicaldrive_item" { physicaldrive_item($ARGV[1], $ARGV[2], $ARGV[3], $ARGV[4]); }
}
