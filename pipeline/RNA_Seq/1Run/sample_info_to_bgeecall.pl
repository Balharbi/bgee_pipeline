#!usr/bin/env perl

use strict;
use warnings;
use diagnostics;
use Getopt::Long;

# Julien Wollbrett, created March 2020

# This script transform the rna_seq_sample_info.txt file into a file used as input to run BgeeCall.

my ($sample_info_file)    = ('');
my ($transcriptome_dir) = ('');
my ($annotation_dir) = ('');
my $fastq_dir = '';
my $bgeecall_file = '';
my $ref_intergenic_dir = '';

my %opts = ('sample_info_file=s'    => \$sample_info_file,      # path to rna_seq_sample_info file
            'transcriptome_dir=s'   => \$transcriptome_dir,     # path to directory containing all transcriptomes
            'annotation_dir=s'      => \$annotation_dir,        # path to directory containing all annotations
            'fastq_dir=s'           => \$fastq_dir,             # path to directory containing all fastq files
            'bgeecall_file=s'       => \$bgeecall_file,         # path to the output file compatible with BgeeCall
            'ref_intergenic_dir=s'  => \$ref_intergenic_dir     # path to directory containing all reference intergenic sequences
           );

# test arguments
my $test_options = Getopt::Long::GetOptions(%opts);
if ( !$test_options || $sample_info_file eq '' || $transcriptome_dir eq '' || $annotation_dir eq '' || $fastq_dir eq '' || $bgeecall_file eq '' || $ref_intergenic_dir eq ''){
    print "\n\tInvalid or missing argument:
\te.g. $0  -sample_info_file=\$(RNASEQ_SAMPINFO_FILEPATH) -transcriptome_dir=\$(RNASEQ_CLUSTER_GTF) -annotation_dir=\$(RNASEQ_CLUSTER_GTF) -fastq_dir=\$(RNASEQ_SENSITIVE_FASTQ) -bgeecall_file=\$(RNASEQ_BGEECALL_FILE) -ref_intergenic_dir=$(CLUSTER_REF_INTERGENIC_FOLDER)
\t-sample_info_file     Path to rna_seq_sample_info file
\t-transcriptome_dir    Path to directory containing all transcriptomes
\t-annotation_dir       Path to directory containing all annotations
\t-fastq_dir            Path to directory containing all FASTQ
\t-bgeecall_file        Path to the output file compatible with BgeeCall
\t-ref_intergenic_dir   Path to directory containing all reference intergenic sequences
\n";
    exit 1;
}

open(FH, '>', $bgeecall_file) or die $!;
# write header
print FH "species_id\trun_ids\treads_size\trnaseq_lib_path\ttranscriptome_path\tannotation_path\toutput_directory\tcustom_intergenic_path\n";


open(my $sample_info, $sample_info_file) || die "failed to read sample info file: $!";
while (my $line = <$sample_info>) {
    chomp $line;
     ## skip comment lines
    next  if ( ($line =~ m/^#/) or ($line =~ m/^\"#/) );
    my @line = split(/\t/, $line);
    my $number_columns = 11;
    if (! scalar @line eq $number_columns) {
        die "all lines of sample info file should have $number_columns columns";
    }
    my $genomeFilePath = $line[4];
    $line[4] =~ m/.+\/(.+)/;
    my $prefixFilePath = $1;
    my $transcriptome_path = "$transcriptome_dir$prefixFilePath.transcriptome.fa.xz";
    my $annotation_path = "$transcriptome_dir$prefixFilePath.gtf_transcriptome";
    my $fastq_path = "$fastq_dir$line[0]";
    my $intergenic_file = "$ref_intergenic_dir$line[2]_intergenic.fa.gz";
    my $output_line = "$line[2]\t\t$line[8]\t$fastq_path\t$transcriptome_path\t$annotation_path\toutput_dir\t$intergenic_file\n";

    print FH $output_line;

}
close(FH);