# Hey emacs! This is a -*- Perl -*- script!
# Util -- Perl utility functions for lintian

# Copyright (C) 1998 Christian Schwarz
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Util;
use strict;
use warnings;

use Exporter;

# Force export as soon as possible, since some of the modules we load also
# depend on us and the sequencing can cause things not to be exported
# otherwise.
our (@ISA, @EXPORT);
BEGIN {
    @ISA = qw(Exporter);
    @EXPORT = qw(parse_dpkg_control
	read_dpkg_control
	get_deb_info
	get_dsc_info
	slurp_entire_file
	get_file_checksum
	file_is_encoded_in_non_utf8
	fail
	system_env
	delete_dir
	copy_dir
	gunzip_file
	touch_file
	perm2oct
	check_path
	resolve_pkg_path);
}

use FileHandle;
use Lintian::Command qw(spawn);
use Lintian::Output qw(string);
use Digest::MD5;

# general function to read dpkg control files
# this function can parse output of `dpkg-deb -f', .dsc,
# and .changes files (and probably all similar formats)
# arguments:
#    $filehandle
#    $debconf_flag (true if the file is a debconf template file)
# output:
#    list of hashes
#    (a hash contains one sections,
#    keys in hash are lower case letters of control fields)
sub parse_dpkg_control {
    my ($CONTROL, $debconf_flag) = @_;

    my @data;
    my $cur_section = 0;
    my $open_section = 0;
    my $last_tag;

    local $_;
    while (<$CONTROL>) {
	chomp;

	# FIXME: comment lines are only allowed in debian/control and should
	# be an error for other control files.
	next if /^\#/;

	# empty line?
	if ((!$debconf_flag && m/^\s*$/) or ($debconf_flag && $_ eq '')) {
	    if ($open_section) { # end of current section
		$cur_section++;
		$open_section = 0;
	    }
	}
	# pgp sig?
	elsif (m/^-----BEGIN PGP SIGNATURE/) { # skip until end of signature
	    while (<$CONTROL>) {
		last if m/^-----END PGP SIGNATURE/o;
	    }
	}
	# other pgp control?
	elsif (m/^-----BEGIN PGP/) { # skip until the next blank line
	    while (<$CONTROL>) {
		last if /^\s*$/o;
	    }
	}
	# new empty field?
	elsif (m/^(\S+):\s*$/o) {
	    $open_section = 1;

	    my ($tag) = (lc $1);
	    $data[$cur_section]->{$tag} = '';

	    $last_tag = $tag;
	}
	# new field?
	elsif (m/^(\S+):\s*(.*)$/o) {
	    $open_section = 1;

	    # Policy: Horizontal whitespace (spaces and tabs) may occur
	    # immediately before or after the value and is ignored there.
	    my ($tag,$value) = (lc $1,$2);
	    $value =~ s/\s+$//;
	    $data[$cur_section]->{$tag} = $value;

	    $last_tag = $tag;
	}
	# continued field?
	elsif (m/^([ \t].*)$/o) {
	    $open_section or fail("syntax error in section $cur_section after the tag $last_tag: $_");

	    # Policy: Many fields' values may span several lines; in this case
	    # each continuation line must start with a space or a tab.  Any
	    # trailing spaces or tabs at the end of individual lines of a
	    # field value are ignored.
	    my $value = $1;
	    $value =~ s/\s+$//;
	    $data[$cur_section]->{$last_tag} .= "\n" . $value;
	}
    }

    return @data;
}

sub read_dpkg_control {
    my ($file, $debconf_flag) = @_;

    if (not _ensure_file_is_sane($file)) {
	return;
    }

    open(my $CONTROL, '<', $file)
	or fail("cannot open control file $file for reading: $!");
    my @data = parse_dpkg_control($CONTROL, $debconf_flag);
    close($CONTROL)
	or fail("pipe for control file $file exited with status: $?");
    return @data;
}

sub get_deb_info {
    my ($file) = @_;

    if (not _ensure_file_is_sane($file)) {
	return;
    }

    # dpkg-deb -f $file is very slow. Instead, we use ar and tar.
    my $opts = { pipe_out => FileHandle->new };
    spawn($opts,
	  ['ar', 'p', $file, 'control.tar.gz'],
	  '|', ['tar', '--wildcards', '-xzO', '-f', '-', '*control'])
	or fail("cannot fork to unpack $file: $opts->{exception}\n");
    my @data = parse_dpkg_control($opts->{pipe_out});

    # Consume all data before exiting so that we don't kill child processes
    # with SIGPIPE.  This will normally only be an issue with malformed
    # control files.
    1 while readline $opts->{pipe_out};
    $opts->{harness}->finish();
    return $data[0];
}

sub get_dsc_info {
    my ($file) = @_;
    my @data = read_dpkg_control($file);
    return (defined($data[0])? $data[0] : undef);
}

sub _ensure_file_is_sane {
    my ($file) = @_;

    # if file exists and is not 0 bytes
    if (-f $file and -s $file) {
	return 1;
    }
    return 0;
}

sub slurp_entire_file {
    my $file = shift;
    open(C, '<', $file)
	or fail("cannot open file $file for reading: $!");
    local $/;
    local $_ = <C>;
    close(C);
    return $_;
}

sub get_file_checksum {
	my ($alg, $file) = @_;
	open (FILE, '<', $file) or fail("Couldn't open $file");
	my $digest;
	if ($alg eq 'md5') {
	    $digest = Digest::MD5->new;
	} elsif ($alg =~ /sha(\d+)/) {
	    require Digest::SHA;
	    $digest = Digest::SHA->new($1);
	}
	$digest->addfile(*FILE);
	close FILE or fail("Couldn't close $file");
	return $digest->hexdigest;
}

sub file_is_encoded_in_non_utf8 {
	my ($file, $type, $pkg) = @_;
	my $non_utf8 = 0;

	open (ICONV, '-|', "env LANG=C iconv -f utf8 -t utf8 \Q$file\E 2>&1")
	    or fail("failure while checking encoding of $file for $type package $pkg");
	my $line = 1;
	while (<ICONV>) {
		if (m/iconv: illegal input sequence at position \d+$/) {
			$non_utf8 = 1;
			last;
		}
		$line++
	}
	close ICONV;

	return $line if $non_utf8;
	return 0;
}

# Just like system, except cleanses the environment first to avoid any strange
# side effects due to the user's environment.
sub system_env {
    my @whitelist = qw(PATH INTLTOOL_EXTRACT LOCPATH);
    my %newenv = map { exists $ENV{$_} ? ($_ => $ENV{$_}) : () } @whitelist;
    my $pid = fork;
    if (not defined $pid) {
	return -1;
    } elsif ($pid == 0) {
	%ENV = %newenv;
	exec @_ or die("exec of $_[0] failed: $!\n");
    } else {
	waitpid $pid, 0;
	return $?;
    }
}

# Translate permission strings like `-rwxrwxrwx' into an octal number.
sub perm2oct {
    my ($t) = @_;

    my $o = 0;

    $t =~ m/^.(.)(.)(.)(.)(.)(.)(.)(.)(.)/o;

    $o += 00400 if $1 eq 'r';	# owner read
    $o += 00200 if $2 eq 'w';	# owner write
    $o += 00100 if $3 eq 'x';	# owner execute
    $o += 04000 if $3 eq 'S';	# setuid
    $o += 04100 if $3 eq 's';	# setuid + owner execute
    $o += 00040 if $4 eq 'r';	# group read
    $o += 00020 if $5 eq 'w';	# group write
    $o += 00010 if $6 eq 'x';	# group execute
    $o += 02000 if $6 eq 'S';	# setgid
    $o += 02010 if $6 eq 's';	# setgid + group execute
    $o += 00004 if $7 eq 'r';	# other read
    $o += 00002 if $8 eq 'w';	# other write
    $o += 00001 if $9 eq 'x';	# other execute
    $o += 01000 if $9 eq 'T';	# stickybit
    $o += 01001 if $9 eq 't';	# stickybit + other execute

    return $o;
}

sub delete_dir {
    return spawn(undef, ['rm', '-rf', '--', @_]);
}

sub copy_dir {
    return spawn(undef, ['cp', '-a', '--', @_]);
}

sub gunzip_file {
    my ($in, $out) = @_;
    spawn({out => $out, fail => 'error'},
	  ['gzip', '-dc', $in]);
}

# create an empty file
# --okay, okay, this is not exactly what `touch' does :-)
sub touch_file {
    open(T, '>', $_[0]) or return 0;
    close(T) or return 0;

    return 1;
}

sub fail {
    my $str;
    if (@_) {
	$str = string('internal error', @_);
    } elsif ($!) {
	$str = string('internal error', $!);
    } else {
	$str = string('internal error');
    }
    $! = 2; # set return code outside eval()
    die $str;
}

#check_path($command)>
#
#Return true if and only if $command is on the executable search path.
#

sub check_path {
    my $command = shift;

    return 0 unless exists $ENV{PATH};
    for my $element (split ':', $ENV{PATH}) {
	next unless length $element;
	return 1 if -f "$element/$command" and -x _;
    }
    return 0;
}

#resolve_pkg_path($curdir, $dest)
#
# Using $curdir as current directory from the (package) root,
# resolve $dest and return (the absolute) path to the destination.
# Note that the result will never start with a slash, even if
# $curdir or $dest does. Nor will it end with a slash.
#
# Note it will return '.' if the result is the package root.
#
# Returns a non-truth value, if it cannot safely resolve the path
# (e.g. $dest would be outside the package root).
#
# Example:
#  resolve_pkg_path('/usr/share/java', '../ant/file') eq  'usr/share/ant/file'
#  resolve_pkg_path('/usr/share/java', '../../../usr/share/ant/file') eq  'usr/share/ant/file'
#  resolve_pkg_path('/', 'usr/..') eq '.';
#
# The following will give a non-truth result:
#  resolve_pkg_path('/usr/bin', '../../../../etc/passwd')
#  resolve_pkg_path('/usr/bin', '/../etc/passwd')
#
sub resolve_pkg_path {
    my ($curdir, $dest) = @_;
    my (@cc, @dc);
    my $target;
    $dest =~ s,//++,/,o;
    # short curcuit $dest eq '/' case.
    return '.' if $dest eq '/';
    # remove any initial ./ and trailing slashes.
    $dest =~ s,^\./,,o;
    $dest =~ s,/$,,o;
    if ($dest =~ m,^/,o){
	# absolute path, strip leading slashes and resolve
	# as relative to the root.
	$dest =~ s,^/,,o;
	return resolve_pkg_path('/', $dest);
    }

    # clean up $curdir (as well)
    $curdir =~ s,//++,/,o;
    $curdir =~ s,/$,,o;
    $curdir =~ s,^/,,o;
    $curdir =~ s,^\./,,o;
    # Short circuit the '.' (or './' -> '') case.
    if ($dest eq '.' or $dest eq '') {
	$curdir =~ s,^/,,o;
	return '.' unless $curdir;
	return $curdir;
    }
    # Relative path from src
    @dc = split(m,/,o, $dest);
    @cc = split(m,/,o, $curdir);
    # Loop through @dc and modify @cc so that in the
    # end of the loop, @cc will contain the path that
    # - note that @cc will be empty if we end in the
    # root (e.g. '/' + 'usr' + '..' -> '/'), this is
    # fine.
    while ($target = shift @dc) {
	if($target eq '..') {
	    # are we out of bounds?
	    return '' unless @cc;
	    # usr/share/java + '..' -> usr/share
	    pop @cc;
	} else {
	    # usr/share + java -> usr/share/java
	    push @cc, $target;
	}
    }
    return '.' unless @cc;
    return join '/', @cc;
}


1;

# Local Variables:
# indent-tabs-mode: t
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 ts=8
