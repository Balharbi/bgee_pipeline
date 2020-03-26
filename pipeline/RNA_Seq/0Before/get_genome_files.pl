#!/usr/bin/env perl

# Perl core modules
use strict;
use warnings;
use diagnostics;

use Getopt::Long;
use FindBin;
use File::Basename;
use LWP::Simple;

#NOTE genome and indexed_genome files MUST be at the same location!

# Define arguments & their default value
my ($GTF_dir, $outDir)               = ('', '');
my ($ensRelease, $ensMetazoaRelease) = (0, 0);
my %opts = ('GTF_dir=s'             => \$GTF_dir,
            'ensRelease=i'          => \$ensRelease,
            'ensMetazoaRelease=i'   => \$ensMetazoaRelease,
            'outDir=s'              => \$outDir,
           );

# Check arguments
my $test_options = Getopt::Long::GetOptions(%opts);
if ( !$test_options || $GTF_dir eq '' || $ensRelease == 0 || $ensMetazoaRelease == 0 || $outDir eq '' ){
    print "\n\tInvalid or missing argument:
\te.g. $0  -GTF_dir=\$(RNASEQGTFDATAPATH) -ensRelease=\$(ENSRELEASE) -ensMetazoaRelease=\$(ENSMETAZOARELEASE) -outDir=\$(RNASEQGTFDATAPATH)
\t-GTF_dir              GTF folder
\t-ensRelease           Ensembl Release number
\t-ensMetazoaRelease    Ensembl Metazoa Release number
\t-outDir               Output Directory to store genome/indexed_genome files
\n";
    exit 1;
}

die "Invalid or missing [$outDir]: $?\n"  if ( !-d $outDir || !-w $outDir );


chdir $outDir; # Go into output/genome folder
for my $gtf (glob($GTF_dir."/*.gtf.gz") ){
    die "Problem with GTF files [$gtf]\n"  if ( -z "$gtf" );

    my $species_name = basename($gtf);
    $species_name   =~ s{^(\w+).+$}{$1};
    $species_name    = lc $species_name;

    my $prefix   = basename($gtf);
    $prefix     =~ s{\.gtf.gz$}{};
    next  if ( -e "$prefix.genome.fa"    && -s "$prefix.genome.fa" );
    if ( is_success( getstore("ftp://ftp.ensembl.org/pub/release-$ensRelease/fasta/$species_name/dna/$prefix.dna.toplevel.fa.gz", "$prefix.genome.fa.gz") ) ){
        # exists in Ensembl FTP && genome file downloaded
        # uncompress downloaded fasta file
        system("gunzip -f $prefix.genome.fa.gz")==0  or die "Failed to unzip genome files: $?\n";

    }
    elsif ( is_success( getstore("ftp://ftp.ensemblgenomes.org/pub/release-$ensMetazoaRelease/metazoa/fasta/$species_name/dna/$prefix.$ensMetazoaRelease.dna.toplevel.fa.gz", "$prefix.genome.fa.gz") ) ){
        # exists in Ensembl Metazoa FTP && GTF file downloaded
        # uncompress downloaded fasta file
        system("gunzip -f $prefix.genome.fa.gz")==0  or die "Failed to unzip genome files: $?\n";

    }
    else {
        warn "No genome GTF file found for [$species_name] in Ensembl $ensRelease or Ensembl Metazoa $ensMetazoaRelease\n";
    }
}

exit 0;

