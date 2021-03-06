package AutomakeWorkspaceCreator;

# ************************************************************
# Description   : A Automake Workspace (Makefile) creator
# Author        : J.T. Conklin & Steve Huston
# Create Date   : 5/13/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;
use File::Copy;

use AutomakeProjectCreator;
use MakePropertyBase;
use WorkspaceCreator;
use WorkspaceHelper;

use vars qw(@ISA);
@ISA = qw(MakePropertyBase WorkspaceCreator);

# ************************************************************
# Data Section
# ************************************************************

my $acfile  = 'configure.ac';
my $acmfile = 'configure.ac.Makefiles';

# ************************************************************
# Subroutine Section
# ************************************************************

sub compare_output {
  return 1;
}

## Can't cache as some intermediate project files are deleted
## and must be regenerated if a project is regenerated.
sub default_cacheok {
  return 0;
}

sub files_are_different {
  my($self, $old, $new) = @_;
  my $diff = 1;
  if (-r $old) {
    my $lh = new FileHandle();
    my $rh = new FileHandle();
    if (open($lh, $old)) {
      if (open($rh, $new)) {
        my $done  = 0;
        my $lline;
        my $rline;

        $diff = 0;
        do {
          $lline = <$lh>;
          $rline = <$rh>;
          if (defined $lline) {
            if (defined $rline) {
              $lline =~ s/#.*//;
              $rline =~ s/#.*//;
              $diff = 1 if ($lline ne $rline);
            }
            else {
              $done = 1;
            }
          }
          else {
            $diff = 1 if (defined $rline);
            $done = 1;
          }
        } while(!$done && !$diff);
        close($rh);
      }
      close($lh);
    }
  }
  return $diff;
}


sub workspace_file_name {
  return $_[0]->get_modified_workspace_name('Makefile', '.am');
}


sub workspace_per_project {
  #my $self = shift;
  return 1;
}


sub pre_workspace {
  my($self, $fh) = @_;
  my $crlf = $self->crlf();

  $self->print_workspace_comment($fh,
            '##  Process this file with automake to create Makefile.in', $crlf,
            '##', $crlf,
            '## ', '$', 'Id', '$', $crlf,
            '##', $crlf,
            '## This file was generated by MPC.  Any changes made directly to', $crlf,
            '## this file will be lost the next time it is generated.', $crlf,
            '##', $crlf,
            '## MPC Command:', $crlf,
            '## ', $self->create_command_line_string($0, @ARGV), $crlf, $crlf);
}


sub write_comps {
  my($self, $fh, $creator, $toplevel) = @_;
  my $projects = $self->get_projects();
  my @list = $self->sort_dependencies($projects);
  my $crlf = $self->crlf();
  my %unique;
  my @dirs;
  my @locals;
  my %proj_dir_seen;
  my $have_subdirs = 0;
  my $outdir = $self->get_outdir();
  my $cond   = '--';

  ## This step writes a configure.ac.Makefiles list into the starting
  ## directory. The list contains of all the Makefiles generated down
  ## the tree. configure.ac can include this to get an up-to-date list
  ## of all the involved Makefiles.
  my $mfh;
  my $makefile;
  if ($toplevel) {
    my $need_acmfile = 1;
    if (! -e "$outdir/$acfile") {
      my $acfh = new FileHandle();
      if (open($acfh, ">$outdir/$acfile")) {
        print $acfh "AC_INIT(", $self->get_workspace_name(), ", 1.0)$crlf",
                    "AM_INIT_AUTOMAKE([1.9])$crlf",
                    $crlf,
                    "AC_PROG_CXX$crlf",
                    "AC_PROG_CXXCPP$crlf",
                    "AC_PROG_LIBTOOL$crlf",
                    $crlf;

        my $fp = $creator->get_feature_parser();
        my $features = $fp->get_names();
        my %assoc = %{$self->get_associated_projects()};
        foreach my $feature (sort @$features) {
          print $acfh 'AM_CONDITIONAL(BUILD_', uc($feature),
                      ', ', ($fp->get_value($feature) ? 'true' : 'false'),
                      ')', $crlf;
          delete $assoc{$feature};
        }
        foreach my $akey (keys %assoc) {
          print $acfh 'AM_CONDITIONAL(BUILD_', uc($akey), ', true)', $crlf
            if ($akey ne $cond);
        }

        print $acfh $crlf,
                    "m4_include([$acmfile])$crlf",
                    $crlf,
                    "AC_OUTPUT$crlf";
        close($acfh);
      }
    }
    else {
      $self->information("$acfile already exists.");
      $need_acmfile = !$self->edit_config_ac("$outdir/$acfile", \@list);
    }

    if ($need_acmfile) {
      unlink("$outdir/$acmfile");
      $mfh = new FileHandle();
      open($mfh, ">$outdir/$acmfile");
      ## The top-level is never listed as a dependency, so it needs to be
      ## added explicitly.
      $makefile = $self->mpc_basename($self->get_current_output_name());
      $makefile =~ s/\.am$//;
      print $mfh "AC_CONFIG_FILES([ $makefile ])$crlf";
      $proj_dir_seen{'.'} = 1;
    }
  }

  ## If we're writing a configure.ac.Makefiles file, every seen project
  ## goes into it. Since we only write this at the starting directory
  ## level, it'll include all projects processed at this level and below.
  foreach my $dep (@list) {
    if ($mfh) {
      ## There should be a Makefile at each level, but it's not a project,
      ## it's a workspace; therefore, it's not in the list of projects.
      ## Since we're consolidating all the project files into one workspace
      ## Makefile.am per directory level, be sure to add that Makefile.am
      ## entry at each level there's a project dependency.
      my $dep_dir = $self->mpc_dirname($dep);
      if (!defined $proj_dir_seen{$dep_dir}) {
        $proj_dir_seen{$dep_dir} = 1;
        ## If there are directory levels between project-containing
        ## directories (for example, at this time in
        ## ACE_wrappers/apps/JAWS/server, there are no projects at the
        ## apps or apps/JAWS level) we need to insert the Makefile
        ## entries for the levels without projects. They won't be listed
        ## in @list but are needed for make to traverse intervening directory
        ## levels down to where the project(s) to build are.
        my @dirs = split /\//, $dep_dir;
        my $inter_dir = "";
        foreach my $dep (@dirs) {
          $inter_dir .= $dep;
          if (!defined $proj_dir_seen{$inter_dir}) {
            $proj_dir_seen{$inter_dir} = 1;
            print $mfh "AC_CONFIG_FILES([ $inter_dir/$makefile ])$crlf";
          }
          $inter_dir .= '/';
        }
        print $mfh "AC_CONFIG_FILES([ $dep_dir/$makefile ])$crlf";
      }
    }

    ## Get a unique list of next-level directories for SUBDIRS.
    ## To make sure we keep the dependencies correct, insert the '.' for
    ## any local projects in the proper place. Remember if any subdirs
    ## are seen to know if we need a SUBDIRS entry generated.
    my $dir = $self->get_first_level_directory($dep);
    if (!defined $unique{$dir}) {
      $unique{$dir} = 1;
      unshift(@dirs, $dir);
    }
    if ($dir eq '.') {
      ## At each directory level, each project is written into a separate
      ## Makefile.<project>.am file. To bring these back into the build
      ## process, they'll be sucked back into the workspace Makefile.am file.
      ## Remember which ones to pull in at this level.
      unshift(@locals, $dep);
    }
    else {
      $have_subdirs = 1;
    }
  }
  close($mfh) if ($mfh);

  # The Makefile.<project>.am files append values to build target macros
  # for each program/library to build. When using conditionals, however,
  # a plain empty assignment is done outside the conditional to be sure
  # that each append can be done regardless of the condition test. Because
  # automake fails if the first isn't a plain assignment, we need to resolve
  # these situations when combining the files. The code below makes sure
  # that there's always a plain assignment, whether it's one outside a
  # conditional or the first append is changed to a simple assignment.
  #
  # We should consider extending this to support all macros that match
  # automake's uniform naming convention.  A true perl wizard probably
  # would be able to do this in a single line of code.

  my %seen;
  my %conditional_targets;
  my %unconditional_targets;
  my %first_instance_unconditional;
  my $installable_headers;
  my $installable_pkgconfig;
  my $includedir;
  my $project_name;
  my $status = 1;
  my $errorString;

  ## To avoid unnecessarily emitting blank assignments, rip through the
  ## Makefile.<project>.am files and check for conditions.
  if (@locals) {
    my $pfh = new FileHandle();
    foreach my $local (reverse @locals) {
      if ($local =~ /Makefile\.(.*)\.am/) {
        $project_name = $1;
      }
      else {
        $project_name = 'nobase';
      }

      if (open($pfh, "$outdir/$local")) {
        my $in_condition = 0;
        my $regok        = $self->escape_regex_special($project_name);
        my $inc_pattern  = $regok . '_include_HEADERS';
        my $pkg_pattern  = $regok . '_pkginclude_HEADERS';
        while (<$pfh>) {
          # Don't look at comments
          next if (/^#/);

          $in_condition++ if (/^if\s*/);
          $in_condition-- if (/^endif\s*/);

          if (   /(^[a-zA-Z][a-zA-Z0-9_]*_(PROGRAMS|LIBRARIES|LTLIBRARIES|LISP|PYTHON|JAVA|SCRIPTS|DATA|SOURCES|HEADERS|MANS|TEXINFOS|LIBADD|LDADD|DEPENDENCIES))\s*\+=\s*/
              || /(^CLEANFILES)\s*\+=\s*/
              || /(^EXTRA_DIST)\s*\+=\s*/
             ) {

            if ($in_condition) {
              $conditional_targets{$1}++;
            } else {
              if (! $seen{$1} ) {
                $first_instance_unconditional{$1} = 1;
              }
              $unconditional_targets{$1}++;
            }
            $seen{$1} = 1;

            $installable_pkgconfig= 1 if (/^pkgconfig_DATA/);
            $installable_headers = 1
                  if (/^$inc_pattern\s*\+=\s*/ || /^$pkg_pattern\s*\+=\s*/);
            }
          elsif (/includedir\s*=\s*(.*)/) {
            $includedir = $1;
          }
        }

        close($pfh);
        $in_condition = 0;
      }
      else {
        $errorString = "Unable to open $local for reading.";
        $status = 0;
        last;
      }
    }
  }

  #
  # Clear seen hash
  #
  %seen = ();

  ## Print out the Makefile.am.
  my $wsHelper = WorkspaceHelper::get($self);
  my $convert_header_name;
  if ($status && ((!defined $includedir && $installable_headers)
      || $installable_pkgconfig)) {
    if (!defined $includedir && $installable_headers) {
      my $incdir = $wsHelper->modify_value('includedir',
                                           $self->get_includedir());
      if ($incdir ne '') {
        print $fh "includedir = \@includedir\@$incdir$crlf";
        $convert_header_name = 1;
      }
    }
    if ($installable_pkgconfig) {
       print $fh "pkgconfigdir = \@libdir\@/pkgconfig$crlf";
    }

    print $fh $crlf;
  }

  if ($status && @locals) {
    ($status, $errorString) = $wsHelper->write_settings($self, $fh, @locals);
  }

  ## Create the SUBDIRS setting.  If there are associated projects, then
  ## we will also set up conditionals for it as well.
  if ($status && $have_subdirs == 1) {
    my $assoc = $self->get_associated_projects();
    my @aorder;
    my %afiles;
    my $entry  = " \\$crlf        ";
    print $fh 'SUBDIRS =';
    foreach my $dir (reverse @dirs) {
      my $found;
      foreach my $akey (keys %$assoc) {
        if (defined $$assoc{$akey}->{$dir}) {
          if ($akey eq $cond) {
            if ($toplevel) {
              print $fh $entry, '@', $dir, '@';
              $found = 1;
            }
          }
          else {
            push(@aorder, $akey);
            push(@{$afiles{$akey}}, $dir);
            $found = 1;
          }
          last;
        }
        elsif ($toplevel && defined $$assoc{$akey}->{uc($dir)} &&
               $akey eq $cond) {
          print $fh $entry, '@', uc($dir), '@';
          $found = 1;
          last;
        }
      }
      print $fh $entry, $dir if (!$found);
    }
    print $fh $crlf;
    my $second = 1;
    foreach my $aorder (@aorder) {
      if (defined $afiles{$aorder}) {
        $second = undef;
        print $fh $crlf,
                  'if BUILD_', uc($aorder), "\n",
                  'SUBDIRS +=';
        foreach my $afile (@{$afiles{$aorder}}) {
          print $fh " $afile";
        }
        delete $afiles{$aorder};
        print $fh $crlf, 'endif', $crlf;
      }
    }
    print $fh $crlf if ($second);
  }

  ## Now, for each target used in a conditional, emit a blank assignment
  ## and mark that we've seen that target to avoid changing the += to =
  ## as the individual files are pulled in.
  if ($status && %conditional_targets) {
    my $primary;
    my $count;

    while ( ($primary, $count) = each %conditional_targets) {
      if (! $first_instance_unconditional{$primary}
          && ($unconditional_targets{$primary} || ($count > 1)))
      {
        print $fh "$primary =$crlf";
        $seen{$primary} = 1;
      }
    }

    print $fh $crlf;
  }

  ## Take the local Makefile.<project>.am files and insert each one here,
  ## then delete it.
  if ($status && @locals) {
    my $pfh = new FileHandle();
    my $liblocs = $self->get_lib_locations();
    my $here = $self->getcwd();
    my $start = $self->getstartdir();
    my %explicit;
    foreach my $local (reverse @locals) {
      if (open($pfh, "$outdir/$local")) {
        print $fh "## $local", $crlf;

        my $look_for_libs = 0;
        my $prev_line;
        my $in_explicit;

        while (<$pfh>) {
          # Don't emit comments
          next if (/^#/);

          # Check for explicit targets
          if ($in_explicit) {
            if (/^\t/) {
              next;
            }
            else {
              $in_explicit = undef;
            }
          }
          elsif ($prev_line !~ /\\$/ && /^([\w\/\.\-\s]+):/) {
            my $target = $1;
            $target =~ s/^\s+//;
            $target =~ s/\s+$//;
            if (defined $explicit{$target}) {
              $in_explicit = 1;
              next;
            }
            else {
              $explicit{$target} = 1;
            }
          }

          if ($convert_header_name) {
            if ($local =~ /Makefile\.(.*)\.am/) {
              $project_name = $1;
            }
            else {
              $project_name = 'nobase';
            }
            my $regok       = $self->escape_regex_special($project_name);
            my $inc_pattern = $regok . '_include_HEADERS';
            my $pkg_pattern = $regok . '_pkginclude_HEADERS';
            if (/^$inc_pattern\s*\+=\s*/ || /^$pkg_pattern\s*\+=\s*/) {
              $_ =~ s/^$regok/nobase/;
            }
          }

          if (   /(^[a-zA-Z][a-zA-Z0-9_]*_(PROGRAMS|LIBRARIES|LTLIBRARIES|LISP|PYTHON|JAVA|SCRIPTS|DATA|SOURCES|HEADERS|MANS|TEXINFOS|LIBADD|LDADD|DEPENDENCIES))\s*\+=\s*/
              || /(^CLEANFILES)\s*\+=\s*/
              || /(^EXTRA_DIST)\s*\+=\s*/
             ) {
            if (!defined ($seen{$1})) {
              $seen{$1} = 1;
              s/\+=/=/;
            }
          }

          ## This scheme relies on automake.mpd emitting the 'la' libs first.
          ## Look for all the libXXXX.la, find out where they are located
          ## relative to the start of the MPC run, and relocate the reference
          ## to that location under $top_builddir. Unless the referred-to
          ## library is in the current directory, then leave it undecorated
          ## so the automake-generated dependency orders the build correctly.
          if ($look_for_libs) {
            my @libs = /\s+(lib(\w+).la)/gm;
            my $libcount = @libs / 2;
            for(my $i = 0; $i < $libcount; ++$i) {
              my $libfile = $libs[$i * 2];
              my $libname = $libs[$i * 2 + 1];
              my $reldir  = $$liblocs{$libname};

              ## If we could not find a relative directory for this
              ## library, it may be that it is a decorated library name.
              ## We will search for an approximate match.
              if (!defined $reldir) {
                my $tmpname = $libname;
                while($tmpname ne '') {
                  $tmpname = substr($tmpname, 0, length($tmpname) - 1);
                  if (defined $$liblocs{$tmpname}) {
                    $reldir = $$liblocs{$tmpname};
                    $self->warning("Relative directory for $libname " .
                                   "was approximated with $tmpname.");
                    last;
                  }
                }
              }

              if (defined $reldir) {
                my $append = ($reldir eq '' ? '' : "/$reldir");
                if ("$start$append" ne $here) {
                  my $mod = $wsHelper->modify_libpath($_, $reldir, $libfile);
                  if (defined $mod) {
                    $_ = $mod;
                  }
                  else {
                    s/$libfile/\$(top_builddir)$append\/$libfile/;
                  }
                }
              }
              else {
                my $mod = $wsHelper->modify_libpath($_, $reldir, $libfile);
                if (defined $mod) {
                  $_ = $mod;
                }
                else {
                  $self->warning("No reldir found for $libname ($libfile).");
                }
              }
            }
            $look_for_libs = 0 if ($libcount == 0);
          }
          $look_for_libs = 1 if (/_LDADD = \\$/ || /_LIBADD = \\$/);

          ## I have introduced a one line delay so that I can simplify
          ## the automake template.  If our current line is empty, then
          ## we will remove the trailing backslash before printing the
          ## previous line.  Automake is horribly unforgiving so we must
          ## avoid this situation at all cost.
          if (defined $prev_line) {
            $prev_line =~ s/\s*\\$// if ($_ =~ /^\s*$/);
            print $fh $prev_line;
          }
          $prev_line = $_;
        }
        ## The one line delay requires that we print out the previous
        ## line (if there was one) when we reach the end of the file.
        if (defined $prev_line) {
          $prev_line =~ s/\s*\\$//;
          print $fh $prev_line;
        }

        close($pfh);
        unlink("$outdir/$local");
        print $fh $crlf;
      }
      else {
        $errorString = "Unable to open $local for reading.";
        $status = 0;
        last;
      }
    }
  }

  ## If this is the top-level Makefile.am, it needs the directives to pass
  ## autoconf/automake flags down the tree when running autoconf.
  ## *** This may be too closely tied to how we have things set up in ACE,
  ## even though it's recommended practice. ***
  if ($status && $toplevel) {
    my $m4inc = '-I m4';
    print $fh $crlf,
              'ACLOCAL = @ACLOCAL@', $crlf,
              'ACLOCAL_AMFLAGS = ',
              (defined $wsHelper ?
                 $wsHelper->modify_value('amflags', $m4inc) : $m4inc), $crlf,
              'AUTOMAKE_OPTIONS = foreign', $crlf, $crlf,
              (defined $wsHelper ?
                 $wsHelper->modify_value('extra', '') : '');
  }

  ## Finish up with the cleanup specs.
  if ($status && @locals) {
    ## There is no reason to emit this if there are no local targets.
    ## An argument could be made that it shouldn't be emitted in any
    ## case because it could be handled by CLEANFILES or a verbatim
    ## clause.

    print $fh '## Clean up template repositories, etc.', $crlf,
              'clean-local:', $crlf,
              "\t-rm -f *~ *.bak *.rpo *.sym lib*.*_pure_* core core.*",
              $crlf,
              "\t-rm -f gcctemp.c gcctemp so_locations *.ics", $crlf,
              "\t-rm -rf cxx_repository ptrepository ti_files", $crlf,
              "\t-rm -rf templateregistry ir.out", $crlf,
              "\t-rm -rf ptrepository SunWS_cache Templates.DB", $crlf;
  }

  return $status, $errorString;
}


sub get_includedir {
  my $self  = shift;
  my $value = $self->getcwd();
  my $start = $self->getstartdir();

  ## Take off the starting directory
  $value =~ s/\Q$start\E//;
  return $value;
}


sub edit_config_ac {
  my($self, $file, $files) = @_;
  my $fh = new FileHandle();
  my $status = 0;

  if (open($fh, $file)) {
    my $crlf   = $self->crlf();
    my @in;
    my @lines;
    my $assoc  = $self->get_associated_projects();
    my $indent = '';
    my %proj_dir_seen;
    my $in_config_files = 0;

    while(<$fh>) {
      my $line = $_;
      push(@lines, $line);

      ## Remove comments and trailing space
      $line =~ s/\bdnl\s+.*//;
      $line =~ s/\s+$//;

      if ($line eq '') {
      }
      elsif ($line =~ /^\s*if\s+test\s+["]?([^"]+)["]?\s*=\s*\w+;\s*then/) {
        ## Entering an if test, save the name
        my $name = $1;
        $name =~ s/\s+$//;
        $name =~ s/.*_build_//;
        push(@in, $name);
      }
      elsif ($line =~ /^\s*if\s+test\s+-d\s+(.+);\s*then/) {
        ## Entering an if test -d, save the name
        my $name = $1;
        $name =~ s/\s+$//;
        $name =~ s/\$srcdir\///;
        push(@in, $name);
      }
      elsif ($line =~ /^\s*fi$/) {
        pop(@in);
      }
      elsif ($line =~ /^(\s*AC_CONFIG_FILES\s*\(\s*\[)/) {
        ## Entering an AC_CONFIG_FILES section, start ignoring the entries
        pop(@lines);
        push(@lines, "$1\n");
        $indent = '  ';
        if ($lines[$#lines] =~ /^(\s+)/) {
          $indent .= $1;
        }
        $in_config_files = 1;
      }
      elsif ($in_config_files) {
        if ($line =~ /(.*)\]\s*\).*/) {
          ## We've reached the end of the AC_CONFIG_FILES section
          my $olast = pop(@lines);
          if ($olast =~ /^[^\s]+(\s*\]\s*\).*)/) {
            $olast = $1;
          }
          ## Add in the Makefiles for this configuration
          if ($#in < 0 && !defined $proj_dir_seen{'.'}) {
            push(@lines, $indent . 'Makefile' . $crlf);
            $proj_dir_seen{'.'} = 1;
          }

          foreach my $dep (@$files) {
            ## First things first, see if we've already seen this
            ## project's directory.  If we have, then there's nothing
            ## else we need to do with it.
            my $dep_dir = $self->mpc_dirname($dep);
            if (!defined $proj_dir_seen{$dep_dir}) {
              my $ok   = 1;
              my @dirs = split(/\//, $dep_dir);
              my $base = $dep;

              if ($base =~ s/\/.*//) {
                my $found = 0;
                foreach my $akey (keys %$assoc) {
                  if (defined $$assoc{$akey}->{$base} ||
                      defined $$assoc{$akey}->{uc($base)}) {
                    if ($#in >= 0) {
                      if (index($base, $in[0]) >= 0) {
                        if ($#in >= 1) {
                          $found = 1;
                          for(my $i = 0; $i <= $#in; $i++) {
                            if (!defined $dirs[$i] ||
                                index($dirs[$i], $in[$i]) < 0) {
                              $found = 0;
                              last;
                            }
                          }
                        }
                        else {
                          ## We need to see into the future here. :-)
                          ## If the second element of @dirs matches an
                          ## association key, we'll guess that there will
                          ## be a "build" section devoted to it.
                          if (!defined $dirs[1] ||
                              !defined $$assoc{$dirs[1]}) {
                            $found = 1;
                          }
                        }
                      }
                    }
                    else {
                      $found = 1;
                    }
                    last;
                  }
                }
                if ($#in >= 0) {
                  $ok = $found;
                }
                else {
                  $ok = !$found;
                }
              }

              if ($ok) {
                $proj_dir_seen{$dep_dir} = 1;
                my $inter_dir = '';
                foreach my $dep (@dirs) {
                  $inter_dir .= $dep;
                  if (!defined $proj_dir_seen{$inter_dir}) {
                    $proj_dir_seen{$inter_dir} = 1;
                    push(@lines, $indent . $inter_dir . "/Makefile$crlf");
                  }
                  $inter_dir .= '/';
                }
                push(@lines, $indent . $dep_dir . "/Makefile$crlf");
              }
            }
          }
          push(@lines, $olast);
          $in_config_files = 0;
        }
        else {
          ## Ignore the entry
          pop(@lines);
        }
      }
    }
    close($fh);

    ## Make a backup and create the new file
    my $backup = $file . '.bak';
    if (copy($file, $backup)) {
      my @buf = stat($file);
      if (defined $buf[8] && defined $buf[9]) {
        utime($buf[8], $buf[9], $backup);
      }
      if (open($fh, ">$file")) {
        foreach my $line (@lines) {
          print $fh $line;
        }
        close($fh);
        $status = 1;
      }
    }
    else {
      $self->warning("Unable to create backup file: $backup");
    }
  }
  return $status;
}

1;
