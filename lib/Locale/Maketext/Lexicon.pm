package Locale::Maketext::Lexicon;
$Locale::Maketext::Lexicon::VERSION = '0.45';

use strict;

=head1 NAME

Locale::Maketext::Lexicon - Use other catalog formats in Maketext

=head1 VERSION

This document describes version 0.45 of Locale::Maketext::Lexicon,
released October 26, 2004.

=head1 SYNOPSIS

As part of a localization class, automatically glob for available
lexicons:

    package Hello::L10N;
    use base 'Locale::Maketext';
    use Locale::Maketext::Lexicon {
        '*' => [Gettext => '/usr/local/share/locale/*/LC_MESSAGES/hello.mo'],
        _decode => 1,   # decode lexicon entries into utf8-strings
    };

Explicitly specify languages, during compile- or run-time:

    package Hello::L10N;
    use base 'Locale::Maketext';
    use Locale::Maketext::Lexicon {
        de => [Gettext => 'hello_de.po'],
        fr => [
            Gettext => 'hello_fr.po',
            Gettext => 'local/hello/fr.po',
        ],
    };
    # ... incrementally add new lexicons
    Locale::Maketext::Lexicon->import({
        de => [Gettext => 'local/hello/de.po'],
    })

Alternatively, as part of a localization subclass:

    package Hello::L10N::de;
    use base 'Hello::L10N';
    use Locale::Maketext::Lexicon (Gettext => \*DATA);
    __DATA__
    # Some sample data
    msgid ""
    msgstr ""
    "Project-Id-Version: Hello 1.3.22.1\n"
    "MIME-Version: 1.0\n"
    "Content-Type: text/plain; charset=iso8859-1\n"
    "Content-Transfer-Encoding: 8bit\n"

    #: Hello.pm:10
    msgid "Hello, World!"
    msgstr "Hallo, Welt!"

    #: Hello.pm:11
    msgid "You have %quant(%1,piece) of mail."
    msgstr "Sie haben %quant(%1,Poststueck,Poststuecken)."

=head1 DESCRIPTION

This module provides lexicon-handling modules to read from other
localization formats, such as I<Gettext>, I<Msgcat>, and so on.

If you are unfamiliar with the concept of lexicon modules, please
consult L<Locale::Maketext> and L<http://www.autrijus.org/webl10n/>
first.

A command-line utility L<xgettext.pl> is also installed with this
module, for extracting translatable strings from source files.

=head2 The C<import> function

The C<import()> function accepts two forms of arguments:

=over 4

=item (I<format> => I<source> ... )

This form takes any number of argument pairs (usually one);
I<source> may be a file name, a filehandle, or an array reference.

For each such pair, it pass the contents specified by the second
argument to B<Locale::Maketext::Lexicon::I<format>>->parse as a
plain list, and export its return value as the C<%Lexicon> hash
in the calling package.

In the case that there are multiple such pairs, the lexicon
defined by latter ones overrides earlier ones.

=item { I<language> => [ I<format>, I<source> ... ] ... }

This form accepts a hash reference.  It will export a C<%Lexicon>
into the subclasses specified by each I<language>, using the process
described above.  It is designed to alleviate the need to set up a
separate subclass for each localized language, and just use the catalog
files.

This module will convert the I<language> arguments into lowercase,
and replace all C<-> with C<_>, so C<zh_TW> and C<zh-tw> will both
map to the C<zh_tw> subclass.

If I<language> begins with C<_>, it is taken as an option that
controls how lexicons are parsed.  See L</Options> for a list
of available options.

The C<*> is a special I<language>; it must be used in conjunction
with a filename that also contains C<*>; all matched files with
a valid language code in the place of C<*> will be automatically
prepared as a lexicon subclass.  If there is multiple C<*> in
the filename, the last one is used as the language name.

=back

=head2 Options

=over 4

=item C<_decode>

If set to a true value, source entries will be converted into
utf8-strings (available in Perl 5.6.1 or later).  This feature
needs the B<Encode> or B<Encode::compat> module.

Currently, only the C<Gettext> backend supports this option.

=item C<_encoding>

This option only has effect when C<_decode> is set to true.
It specifies an encoding to store lexicon entries, instead of
utf8-strings.

If C<_encoding> is set to C<locale>, the encoding from the
current locale setting is used.

=head2 Subclassing format handlers

If you wish to override how sources specified in different data types
are handled, please use a subclass that overrides C<lexicon_get_I<TYPE>>.

XXX: not documented well enough yet.  Patches welcome.

=head1 NOTES

If you want to implement a new C<Lexicon::*> backend module, please note
that C<parse()> takes an array containing the B<source strings> from the
specified filehandle or filename, which are I<not> C<chomp>ed.  Although
if the source is an array reference, its elements will probably not contain
any newline characters anyway.

The C<parse()> function should return a hash reference, which will be
assigned to the I<typeglob> (C<*Lexicon>) of the language module.  All
it amounts to is that if the returned reference points to a tied hash,
the C<%Lexicon> will be aliased to the same tied hash if it was not
initialized previously.

=cut

our %Opts;
sub option { shift if ref($_[0]); $Opts{lc $_[0]} }
sub set_option { shift if ref($_[0]); $Opts{lc $_[0]} = $_[1] }

sub encoding {
    my $encoding = option(@_, 'encoding') or return;
    return $encoding unless lc($encoding) eq 'locale';

    no warnings 'uninitialized';
    my ($country_language, $locale_encoding);

    local $@;
    eval {
        require I18N::Langinfo;
        $locale_encoding = I18N::Langinfo::langinfo(I18N::Langinfo::CODESET());
    } or eval {
        require Win32::Console;
        $locale_encoding = 'cp'.Win32::Console::OutputCP();
    };
    if (!$locale_encoding) {
        foreach my $key (qw( LANGUAGE LC_ALL LC_MESSAGES LANG )) {
            $ENV{$key} =~ /^([^.]+)\.([^.:]+)/ or next;
            ($country_language, $locale_encoding) = ($1, $2);
            last;
        }
    }
    if (defined $locale_encoding &&
        lc($locale_encoding) eq 'euc' &&
        defined $country_language) {
        if ($country_language =~ /^ja_JP|japan(?:ese)?$/i) {
            $locale_encoding = 'euc-jp';
        } elsif ($country_language =~ /^ko_KR|korean?$/i) {
            $locale_encoding = 'euc-kr';
        } elsif ($country_language =~ /^zh_CN|chin(?:a|ese)?$/i) {
            $locale_encoding = 'euc-cn';
        } elsif ($country_language =~ /^zh_TW|taiwan(?:ese)?$/i) {
            $locale_encoding = 'euc-tw';
        }
    }

    return $locale_encoding;
}

sub import {
    my $class = shift;
    return unless @_;

    my %entries;
    if (UNIVERSAL::isa($_[0], 'HASH')) {
        # a hashref with $lang as keys, [$format, $src ...] as values
        %entries = %{$_[0]};
    }
    elsif (@_ % 2) {
        %entries = ( '' => [ @_ ] );
    }

    # expand the wildcard entry
    if (my $wild_entry = delete $entries{'*'}) {
        while (my ($format, $src) = splice(@$wild_entry, 0, 2)) {
            next if ref($src); # XXX: implement globbing for the 'Tie' backend

            my $pattern = quotemeta($src);
            $pattern =~ s/\\\*(?=[^*]+$)/\([-\\w]+\)/g or next;
            $pattern =~ s/\\\*/.*?/g;
            $pattern =~ s/\\\?/./g;
            $pattern =~ s/\\\[/[/g;
            $pattern =~ s/\\\]/]/g;
            $pattern =~ s[\\\{(.*?)\\\\}][
                '(?:'.join('|', split(/,/, $1)).')'
            ]eg;

            require File::Glob;
            foreach my $file (File::Glob::bsd_glob($src)) {
                $file =~ /$pattern/ or next;
                push @{$entries{$1}}, ($format => $file) if $1;
            }
            delete $entries{$1}
                unless !defined($1)
                    or exists $entries{$1} and @{$entries{$1}};
        }
    }

    %Opts = ();
    foreach my $key (grep /^_/, keys %entries) {
        set_option(lc(substr($key, 1)) => delete($entries{$key}));
    }
    my $OptsRef = { %Opts };

    while (my ($lang, $entry) = each %entries) {
        my $export = caller;

        if (length $lang) {
            # normalize language tag to Maketext's subclass convention
            $lang = lc($lang);
            $lang =~ s/-/_/g;
            $export .= "::$lang";
        }

        my @pairs = @{$entry||[]} or die "no format specified";

        while (my ($format, $src) = splice(@pairs, 0, 2)) {
            if (defined($src) and !ref($src) and $src =~ /\*/) {
                unshift(@pairs, $format => $_) for File::Glob::bsd_glob($src);
                next;
            }

            my @content = $class->lexicon_get($src, scalar caller, $lang);

            no strict 'refs';
            eval "use $class\::$format; 1" or die $@;

            if (defined %{"$export\::Lexicon"}) {
                if (ref(tied %{"$export\::Lexicon"}) eq __PACKAGE__) {
                    tied(%{"$export\::Lexicon"})->_force;
                }
                # be very careful not to pollute the possibly tied lexicon
                *{"$export\::Lexicon"} = {
                    %{"$export\::Lexicon"},
                    %{"$class\::$format"->parse(@content)},
                };
            }
            else {
                my $promise;
                tie %{"$export\::Lexicon"}, __PACKAGE__, {
                    Opts => $OptsRef,
                    Export => "$export\::Lexicon",
                    Class => "$class\::$format",
                    Content => \@content,
                };
            }

            push(@{"$export\::ISA"}, scalar caller) if length $lang;
        }
    }
}

sub TIEHASH {
    my ($class, $args) = @_;
    return bless($args, $class);

}

{
    no strict 'refs';
    sub _force {
        my $args = shift;
        if (!$args->{Done}++) {
            local *Opts = $args->{Opts};
            *{$args->{Export}} = $args->{Class}->parse(@{$args->{Content}});
        }
        return \%{$args->{Export}};
    }
    sub FETCH { _force($_[0])->{$_[1]} }
    sub EXISTS { exists _force($_[0])->{$_[1]} }
    sub DELETE { delete _force($_[0])->{$_[1]} }
    sub SCALAR { scalar %{_force($_[0])} }
    sub STORE { _force($_[0])->{$_[1]} = $_[2] }
    sub CLEAR { %{_force($_[0])->{$_[1]}} = () }
    sub NEXTKEY { each %{_force($_[0])} }
    sub FIRSTKEY {
        my $hash = _force($_[0]);
        my $a = scalar keys %$hash;
        each %$hash;
    }
}

sub lexicon_get {
    my ($class, $src, $caller, $lang) = @_;
    return unless defined $src;

    foreach my $type (qw(ARRAY HASH SCALAR GLOB), ref($src)) {
        next unless UNIVERSAL::isa($src, $type);

        my $method = 'lexicon_get_' . lc($type);
        die "cannot handle source $type for $src: no $method defined"
            unless $class->can($method);

        return $class->$method($src, $caller, $lang);
    }

    # default handler
    return $class->lexicon_get_($src, $caller, $lang);
}

# for scalarrefs and arrayrefs we just dereference the $src
sub lexicon_get_scalar { ${$_[1]} }
sub lexicon_get_array  { @{$_[1]} }

sub lexicon_get_hash   {
    my ($class, $src, $caller, $lang) = @_;
    return map { $_ => $src->{$_} } sort keys %$src;
}

sub lexicon_get_glob   {
    my ($class, $src, $caller, $lang) = @_;

    no strict 'refs';

    # be extra magical and check for DATA section
    if (eof($src) and $src eq \*{"$caller\::DATA"} or $src eq \*{"main\::DATA"}) {
        # okay, the *DATA isn't initiated yet. let's read.
        #
        require FileHandle;
        my $fh = FileHandle->new;
        my $package = ( ($src eq \*{"main\::DATA"}) ? 'main' : $caller );

        if ( $package eq 'main' and -e $0 ) {
            $fh->open($0) or die "Can't open $0: $!";
        }
        else {
            my $level = 1;
            while ( my ($pkg, $filename) = caller($level++) ) {
                next unless $pkg eq $package;
                next unless -e $filename;
                next;

                $fh->open($filename) or die "Can't open $filename: $!";
                last;
            }
        }

        while (<$fh>) {
            # okay, this isn't foolproof, but good enough
            last if /^__DATA__$/;
        }

        return <$fh>;
    }

    # fh containing the lines
    my $pos = tell($src);
    my @lines = <$src>;
    seek($src, $pos, 0);
    return @lines;
}

# assume filename - search path, open and return its contents
sub lexicon_get_ {
    my ($class, $src, $caller, $lang) = @_;

    require FileHandle;
    require File::Spec;

    my $fh = FileHandle->new;
    my @path = split('::', $caller);
    push @path, $lang if length $lang;

    $src = (grep { -e } map {
        my @subpath = @path[0..$_];
        map { File::Spec->catfile($_, @subpath, $src) } @INC;
    } -1 .. $#path)[-1] unless -e $src;

    die "cannot find $_[1] (called by $_[2]) in \@INC" unless -e $src;
    $fh->open($src) or die $!;
    binmode($fh);
    return <$fh>;
}

1;

=head1 ACKNOWLEDGMENTS

Thanks to Jesse Vincent for suggesting this module to be written.

Thanks also to Sean M. Burke for coming up with B<Locale::Maketext>
in the first place, and encouraging me to experiment with alternative
Lexicon syntaxes.

Thanks also to Yi Ma Mao for providing the MO file parsing subroutine,
as well as inspiring me to implement file globbing and transcoding
support.

See the F<AUTHORS> file in the distribution for a list of people who
have sent helpful patches, ideas or comments.

=head1 SEE ALSO

L<xgettext.pl> for extracting translatable strings from common template
systems and perl source files.

L<Locale::Maketext>, L<Locale::Maketext::Lexicon::Auto>,
L<Locale::Maketext::Lexicon::Gettext>, L<Locale::Maketext::Lexicon::Msgcat>,
L<Locale::Maketext::Lexicon::Tie>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2002, 2003, 2004 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
