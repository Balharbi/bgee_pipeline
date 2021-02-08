#!/usr/bin/env perl

use strict;
use warnings;
use diagnostics;

use File::Slurp;

my $annotation_file = $ARGV[0]  // die "\n\t$0 <RNASeq library annotation file (rna_seq_sample_info.txt)> <RNASeq library already downloaded (rna_seq_sample_downloaded.txt)> [info_only]\n\n";
my $downloaded_lib  = $ARGV[1]  // die "\n\t$0 <RNASeq library annotation file (rna_seq_sample_info.txt)> <RNASeq library already downloaded (rna_seq_sample_downloaded.txt)> [info_only]\n\n";
my $info_only       = $ARGV[2]  // 0;


my $SRATK_PATH         = $ENV{'SRATK_PATH'};
#my $ASPERA_CONNECT_DIR = $ENV{'ASPERA_CONNECT_DIR'};

my $BASE               = "/scratch/wally/FAC/FBM/DEE/mrobinso/bgee";
my $SRA_PATH           = $BASE.'/sra';
my $FASTQ_PATH         = $BASE.'/FASTQ/RNAseq';


# Private experimentId to store encrypted
my @private_exp_id     = ('SRP012682'); # E.g. GTEx


#if ( !$SRATK_PATH || !$ASPERA_CONNECT_DIR ){
#    die "\n\tSRATK_PATH and/or ASPERA_CONNECT_DIR not defined! They are used to find NCBI SRA & ASPERA executables\n\n";
#}
if ( !$SRATK_PATH ){
    die "\n\tSRATK_PATH not defined! It is used to find NCBI SRA executables\n\n";
}


# Read already downloaded libraries
my %already_downloaded = map { $_ => 1 } read_file("$downloaded_lib", chomp=>1);


open(my $ANNOTATION, '<', "$annotation_file")  or die "\n\tCannot read/open [$annotation_file]\n\n";
#libraryId   experimentId   speciesId   organism        genomeFilePath                        database   platform                       libraryType   libraryInfo   readLength   runIds
#SRX081869   GSE30352       9031        Gallus gallus   gallus_gallus/Gallus_gallus.Galgal4   Ensembl    Illumina Genome Analyzer IIx   SINGLE                      76           SRR306710
my $count = 0;
my @missing;
LIB:
while (<$ANNOTATION>){
    chomp $_;
    my @tmp = map { s{^"|"$}{}g; $_ } # remove quotes
              split(/\t/, $_);
    my $sra_list   = $tmp[10];
    my $library_id = $tmp[0];
    my $exp_id     = $tmp[1];
    next LIB  if ( $library_id =~ /^#/ || $sra_list =~ /^#/ ); # Header or commented line
    next LIB  if ( exists $already_downloaded{$library_id} );

    print "Starting [$library_id]\t"  if ( !$info_only );
    SRA:
    for my $sra_id ( sort split(/,/, $sra_list) ){
        if ( $sra_id =~ /^[SEDC]RR\d+/ ){ #S: SRA/NCBI; E: EBI; D: DDBJ; C: GSA_China
            # Check if FASTQ are there AND if SRA have been removed  -> already stored
            if ( !-e "$SRA_PATH/$sra_id.sra" && (-s "$FASTQ_PATH/$library_id/$sra_id.fastq.gz" || -s "$FASTQ_PATH/$library_id/$sra_id.fastq.gz.enc") ){
                warn "\t[$library_id/$sra_id] single-end already stored\n"  if ( !$info_only );
                next SRA;
            }
            if ( !-e "$SRA_PATH/$sra_id.sra" && (-s "$FASTQ_PATH/$library_id/${sra_id}_1.fastq.gz" || -s "$FASTQ_PATH/$library_id/${sra_id}_1.fastq.gz.enc")
                                             && (-s "$FASTQ_PATH/$library_id/${sra_id}_2.fastq.gz" || -s "$FASTQ_PATH/$library_id/${sra_id}_2.fastq.gz.enc")){
                warn "\t[$library_id/$sra_id] paired-end already stored\n"  if ( !$info_only );
                next SRA;
            }
            if ( $info_only ){
                push @missing, join("\t", @tmp);
                next LIB;
            }

            # Run prefetch to get SRA file
            #NOTE prefetch automatically checks what has already been downloaded and completes if needed
            #NOTE cd to the "project's workspace directory" the ONLY place where the SRA download works for private SRR
#            system("cd $BASE; $SRATK_PATH/bin/prefetch --max-size 500G -t ascp -a \"$ASPERA_CONNECT_DIR/bin/ascp|$ASPERA_CONNECT_DIR/etc/asperaweb_id_dsa.openssh\" $sra_id")==0
             system("cd $BASE; $SRATK_PATH/bin/prefetch --max-size 500G $sra_id")==0
                or do { warn "\tFailed to get [$library_id/$sra_id]\n"; next SRA };

            # Convert in FastQ
            #   Transforming ".sra" file into ".fastq" file using fastq-dump software, the option --split-3 cause splitting paired reads into separate files '_1.fastq' and '_2.fastq',
            #   output files go to sample subfolder in fastq folder
            #NOTE fastq-dump has problems with paths containing //
            #NOTE cd to the "project's workspace directory" the ONLY place where the SRA download works for private SRR
            mkdir "$FASTQ_PATH/$library_id";
            system("cd $BASE; $SRATK_PATH/bin/fastq-dump --split-e --gzip --outdir $FASTQ_PATH/$library_id/  $SRA_PATH/$sra_id.sra")==0
                or do { warn "\tFailed to convert [$library_id/$sra_id]\n"; next SRA };

            # Check FastQ file size
            for my $fastq ( glob("$FASTQ_PATH/$library_id/*.gz") ){
                if ( -s $fastq < 1_000_000 ){
                    warn "$fastq file size looks very small!";
                }
            }

            my $prefix      = "$FASTQ_PATH/$library_id/$sra_id";
            my $fastq_fastp = '';
            my $fastq_R     = '';
            ## Single-end
            if ( -s "$prefix.fastq.gz" ){
                $fastq_fastp = "$prefix.fastq.gz";
                $fastq_R     = $fastq_fastp;
            }
            ## Paired-end
            elsif ( -s "${prefix}_1.fastq.gz" && -s "${prefix}_2.fastq.gz" ){
                $fastq_fastp = "${prefix}_1.fastq.gz -I ${prefix}_2.fastq.gz";
                $fastq_R     = "${prefix}_1.fastq.gz    ${prefix}_2.fastq.gz";
            }
            # Run FastP (A quality control tool for high throughput sequence data) for ALL SRR (runs)
            # as well as basic read length statistics with R
            #NOTE Would be nice to have all basic stats from FastP (currently some are done in R)
            if ( !-e "$prefix.fastp.html.xz" || !-e "$prefix.fastp.json.xz" ){
                system("fastp -i $fastq_fastp --json $prefix.fastp.json --html $prefix.fastp.html --thread 2  > $prefix.fastp.log 2>&1")==0
                    or do { warn "\tfastp failed for [$prefix]\n" };
                system("xz -9 $prefix.fastp.html $prefix.fastp.json");
            }
            if ( !-e "$prefix.R.stat" ){
                #FIXME echo -e does not look to be valid anymore in recent Linux and Mac OS
                system("echo -e \"#min\tmax\tmedian\tmean\" > $prefix.R.stat");
                system("zcat $fastq_R | sed -n '2~4p' | awk '{print length(\$0)}' | Rscript -e 'd<-scan(\"stdin\", quiet=TRUE);cat(min(d), max(d), median(d), mean(d), sep=\"\\t\");cat(\"\\n\")' >> $prefix.R.stat");
            }

            # If private (need encryption):
            if ( (scalar grep { /^$exp_id$/ } @private_exp_id) >= 1 ){
                for my $fastq ( glob("$FASTQ_PATH/$library_id/*.gz") ){
                    #NOTE Replace -salt by -d for decrypting and gz.enc as input and gz as output
                    system("openssl enc -aes-128-cbc -salt -in $fastq -out $fastq.enc -pass file:$BASE/.passw  &&  rm -f $fastq")==0
                        or do { warn "\tFailed to encrypt [$library_id/$sra_id]\n"; next SRA };
                }
            }

            # If fine, SRA cleaning
            system("rm -f $SRA_PATH/$sra_id.sra*");
        }
        else {
            warn "\t[$sra_id] is not an SRA id\n";
            system("rm -f $SRA_PATH/$sra_id.sra*");
        }
    }
    print "Ending [$library_id]\n\n"  if ( !$info_only );
    $count++;
}
close $ANNOTATION;

if ( $info_only ){
    my $missing = scalar @missing;
    print join("\n", @missing), "\n";
    print "#$missing libraries missing\n";
}
else {
    print "\n$count libraries downloaded\n";
}
exit 0;

