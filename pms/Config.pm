package Ilbot::Config;
use 5.010;
use strict;
use warnings;
use Config::File qw/read_config_file/;
use HTML::Template 2.91;
use Data::Dumper;

use parent 'Exporter';
our @EXPORT = qw/chan_conf  config _template _backend _frontend _json_frontend _search_backend sanitize_channel_for_fs/;

my $path;
my %config;

my %known_files = (
    www     => 1,
    search  => 1,
);

my %defaults = (
    www => {
        base_url        => '/',
        no_cache        => 0,
        throttle        => 0,
        use_cache       => 0,
        logo_url        => '/s/woodcoin.png',
        logo_link       => 'http://woodcoin.org/',
        logo_alt        => 'Woodcoin',
        chan_conf       => {},
    },
    backend => {
        timezone        => 'utc',
        timezone_descr  => "the server's local time",
        use_cache       => 1,
        log_joins       => 1,
        temp_path       => '/tmp/ilbot',
    },
    search => {
        language        => 'en',
        context         => 4,
    }
);

sub import {
    unless (defined $path) {
        my @config_paths = (@_,  'config', '/etc/ilbot');
        for my $p (@config_paths) {
            if (-e "$p/backend.conf") {
                $path = $p;
                last;
            }
        }
        unless (defined $path) {
            die "Cannot find config file 'backend.conf' in any of these directories:\n"
                . join(', '), map qq['$_'], @config_paths;
        }
    }
    unless (-d "$path/template") {
        die "Missing directory '$path/template'";
    }
    $config{config_root} = $path;
    $config{template}    = "$path/template";
    $config{backend}     = read_config_file("$path/backend.conf");
    $config{search_idx_root} = "$path/../search-idx";
    if (defined $config{backend}{lib}) {
        unshift @INC, split /:/, $config{backend}{lib}
    }
    __PACKAGE__->export_to_level(1, __PACKAGE__, @EXPORT);
}

sub config {
    my @keys = @_;
    my $first = $keys[0];
    if ($known_files{$first}) {
        $config{$first} //= read_config_file("$path/$first.conf");
    }
    my $c = \%config;
    my $d = \%defaults;
    for (@keys) {
        $c = $c->{$_};
        $d = $d->{$_};
        $c //= $d;
        unless (defined $c) {
            die "Can't find config for @keys (config missing from $_)";
        }
    }
    return $c;
}

sub chan_conf {
    my ( $chan, $key ) = @_;
    my $conf = config( www => 'chan_conf' ) or return;
    $conf->{$chan} or return;
    return $conf->{$chan}{$key};
}

sub _template {
    my $name = shift;

    my @args = (
        loop_context_vars   => 1,
        global_vars         => 1,
        die_on_bad_params   => 0,
        default_escape      => 'html',
        utf8                => 1,
    );

    my $classname = 'HTML::Template';
    eval {
        require 'HTML/Template/Compiled.pm';
        my $temp_path = config(backend => 'temp_path');
        mkdir $temp_path unless -d $temp_path;
        my $cache_dir = join '/', $temp_path, 'templates';
        mkdir $cache_dir unless -d $cache_dir;
        if (-d $cache_dir && -w $cache_dir) {
            $classname = 'HTML::Template::Compiled';
            push @args, (
                file_cache => 1,
                file_cache_dir => $cache_dir,
                case_sensitive  => 0,
            );
        }
    };
#    warn $@ if $@;

    if (ref $name) {
        return $classname->new(
            scalarref   => $name,
            path        => config('template'),
            @args,
        );
    } else {
        my $path = config('template') . "/$name.tmpl";
        return $classname->new(
            filename            => $path,
            @args,
        );
    }
}

sub _backend {
    require Ilbot::Backend::SQL;
    my $sql = Ilbot::Backend::SQL->new(
        config  => config('backend'),
    );
    if (config(backend => 'use_cache')) {
        require Ilbot::Backend::Cached;
        return Ilbot::Backend::Cached->new(
            backend  => $sql,
        );
    }
    return $sql;
}

sub _search_backend {
    require Ilbot::Backend::Search;
    return Ilbot::Backend::Search->new(
        backend => _backend(),
    );
}

sub _frontend {
    require Ilbot::Frontend;
    my $f = Ilbot::Frontend->new(
        backend => _backend(),
    );
    if (config(www => 'use_cache')) {
        require Ilbot::Frontend::Cached;
        return Ilbot::Frontend::Cached->new(
            frontend => $f,
            backend  => $f->backend,
        );
    }
    return $f;
}

sub _json_frontend {
    require Ilbot::Frontend::JSON;
    return Ilbot::Frontend::JSON->new(
        backend => _backend(),
    );
}

sub sanitize_channel_for_fs {
    my $c = shift;
    $c =~ tr/a-zA-Z0-9_-//cd;
    return $c;
}

1;
