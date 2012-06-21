PHYML=phyml
PAUPRAT=pauprat
PAUP=paup
JAVA=java
CODONML=codonml
SCRIPT=script
LIB=lib
PERL=perl -I$(LIB)
DATA=data
RAWDATA=$(DATA)/raw/
SOURCETREES=$(DATA)/sourcetrees
TAXAMAP=$(DATA)/excel/taxa.csv
SPECIESPHYLOXML=$(DATA)/speciestree.xml
RAWFILES := $(wildcard $(RAWDATA)/*.raw)
CONTREES := $(wildcard $(RAWDATA)/*.tre)
NEXMLFILES := $(wildcard $(SOURCETREES)/*.xml)

# variables for NCBI taxonomy tree
NCBISTEM=phyliptree
NCBITREE=$(DATA)/$(NCBISTEM).phy
NCBIMRP=$(SOURCETREES)/$(NCBISTEM).dat

# variables for supertree
SUPERTREE=$(DATA)/supertree
SUPERMRPSTEM=MRP_matrix
SUPERMRP=$(SUPERTREE)/$(SUPERMRPSTEM).nex
MRPOUTGROUP=mrp_outgroup
RATCHETSETUP=setup.nex
RATCHETCOMMANDS=ratchet.nex
RATCHETCOMMANDSABS=$(SUPERTREE)/$(RATCHETCOMMANDS)
RATCHETRESULT=$(SUPERTREE)/mydata.tre
RATCHETFILES=$(SUPERTREE)/mydata.tre $(SUPERTREE)/mydata.tmp $(RATCHETCOMMANDSABS) $(SUPERMRP) $(SUPERTREE)/paupratchet.log

# these are files that are going to be generated by various targets
FASTAFILES  = $(patsubst %.raw,%.fas,$(RAWFILES))
PHYLIPFILES = $(patsubst %.fas,%.phylip,$(FASTAFILES))
NEWICKTREES = $(patsubst %.tre,%.dnd,$(CONTREES))
PAMLTREES   = $(patsubst %.dnd,%.pamltree,$(NEWICKTREES))
PAMLCTLS    = $(patsubst %.dnd,%.pamlctl,$(NEWICKTREES))
PAMLOUTS    = $(patsubst %.pamlctl,%.pamlout,$(PAMLCTLS))
PHYMLTREES  = $(patsubst %.phylip,%.phylip_phyml_tree.txt,$(PHYLIPFILES))
PHYLOXMLGENETREES = $(patsubst %.phylip_phyml_tree.txt,%.phyloxml,$(PHYMLTREES))
NEXUSFILES = $(patsubst %.phylip_phyml_tree.txt,%.nex,$(PHYMLTREES))
SVGFILES = $(patsubst %.nex,%.svg,$(NEXUSFILES))
CSVFILES = $(patsubst %.nex,%.csv,$(NEXUSFILES))
MRPMATRICES = $(patsubst %.xml,%.dat,$(NEXMLFILES))
SDITREES = $(patsubst %.phyloxml,%.sdi,$(PHYLOXMLGENETREES))

.PHONY : clean all genetrees speciestree sdi treebase

all : genetrees speciestree sdi

genetrees : $(FASTAFILES) $(PHYLIPFILES) $(NEWICKTREES) $(PHYMLTREES) $(PHYLOXMLGENETREES) $(NEXUSFILES) $(SVGFILES)

paml : $(PAMLOUTS)

speciestree : $(SPECIESPHYLOXML)

sdi : $(SPECIESPHYLOXML) $(PHYLOXMLGENETREES) $(SDITREES)

treebase :
	$(PERL) $(SCRIPT)/fetch_trees.pl -d $(SOURCETREES) -c $(TAXAMAP)

# clean up nick's raw fasta files
$(FASTAFILES) : %.fas : %.raw
	cat $< | $(PERL) $(SCRIPT)/filter_frameshifts.pl -c $(TAXAMAP) \
        | $(PERL) $(SCRIPT)/filter_sparse_codons.pl \
        | $(PERL) $(SCRIPT)/filter_short_seqs.pl -c $(TAXAMAP) -i OPHIHANN -i ANOLCARO \
        | $(PERL) $(SCRIPT)/filter_duplicate_seqs.pl > $@

# converts fasta files to phylip files for phyml
$(PHYLIPFILES) : %.phylip : %.fas
	$(PERL) $(SCRIPT)/fas2phylip.pl -i $< -c $(TAXAMAP) > $@

# converts nick's consensus nexus trees to newick trees and uses them as
# input trees for a phyml run on the filtered alignments
$(PHYMLTREES) : %.phylip_phyml_tree.txt : %.phylip
	$(PERL) $(SCRIPT)/nexus2newick.pl -c $(TAXAMAP) -i $*.tre -s $*.fas > $*.dnd
	$(PERL) -i $(SCRIPT)/nodelabels.pl $*.dnd
	$(PHYML) -i $< -u $*.dnd -s BEST

# generate trees with labeled internal nodes for PAML codeml
$(PAMLTREES) : %.pamltree : %.dnd
	$(PERL) $(SCRIPT)/make_paml_tree.pl -c $(TAXAMAP) -i $< > $@

# generate paml control files
$(PAMLCTLS) : %.pamlctl : %.dnd
	$(PERL) $(SCRIPT)/make_paml_ctl.pl -t $< -s $*.phylip -o $*.pamlout > $@

# run codonml
$(PAMLOUTS) : %.pamlout : %.pamlctl
	$(CODONML) $<

# generates phyloxml trees
$(PHYLOXMLGENETREES) : %.phyloxml : %.phylip_phyml_tree.txt
	$(PERL) $(SCRIPT)/phyloxml.pl -s $* -f newick -c $(TAXAMAP) > $@

# generates nexus files
$(NEXUSFILES) : %.nex : %.phylip_phyml_tree.txt
	$(PERL) $(SCRIPT)/make_nexus.pl \
        --treefile=$< \
        --treeformat=newick \
        --labels \
        --datafile=$*.phylip \
        --dataformat=phylip \
        --datatype=dna > $@

# generate tree images
$(SVGFILES) : %.svg : %.nex
	$(PERL) $(SCRIPT)/color_branches.pl \
        --csv=$(TAXAMAP) \
        --nexus=$< \
        --hyphy=$*.csv \
        --param=omega3 \
        --verbose \
        --define width=1200 \
        --define height=auto \
        --define format=svg \
        --define shape=rect \
        --define mode=clado \
        --define text_width=300 \
        --define text_vert_offset=8 > $@

# converts downloaded source trees to mrp matrices
$(MRPMATRICES) : %.dat : %.xml
	$(PERL) $(SCRIPT)/treebase2mrp.pl -i $< -f nexml -c $(TAXAMAP) > $@

# converts the NCBI common tree to mrp matrix
$(NCBIMRP) :
	$(PERL) $(SCRIPT)/ncbi2mrp.pl -i $(NCBITREE) -f newick -c $(TAXAMAP) > $@

# concatenates mrp matrices from treebase and ncbi common tree to nexus file
$(SUPERMRP) : $(NCBIMRP) $(MRPMATRICES)
	$(PERL) $(SCRIPT)/concat_tables.pl -d $(SOURCETREES) -c $(TAXAMAP) \
        -o $(MRPOUTGROUP) > $@

# appends command blocks to mrp nexus file
$(RATCHETCOMMANDSABS) : $(SUPERMRP)
	cd $(SUPERTREE) && $(PAUPRAT) $(RATCHETSETUP) && cd -
	$(PERL) $(SCRIPT)/make_ratchet_footer.pl --constraint $(NCBITREE) \
        -f newick -o $(MRPOUTGROUP) --csv $(TAXAMAP) -r $(RATCHETCOMMANDS) \
        >> $(SUPERMRP)

# runs the parsimony ratchet
$(RATCHETRESULT) : $(RATCHETCOMMANDSABS)
	cd $(SUPERTREE) && $(PAUP) $(SUPERMRPSTEM).nex && cd -

# makes consensus species tree in phyloxml format
$(SPECIESPHYLOXML) : $(RATCHETRESULT)
	$(PERL) $(SCRIPT)/make_consensus.pl -i $(RATCHETRESULT) -c $(TAXAMAP) \
        -o $(MRPOUTGROUP) > $@

# runs the sdi analysis, this requires that forester.jar is in the $CLASSPATH
$(SDITREES) : %.sdi : %.phyloxml
	$(JAVA) org.forester.application.sdi $< $(SPECIESPHYLOXML) $@

clean :
	rm -f $(FASTAFILES) $(PHYLIPFILES) $(NEWICKTREES) $(PHYMLTREES) \
        $(PHYLOXMLGENETREES) $(MRPMATRICES) $(NCBIMRP) $(RATCHETFILES) \
        $(SPECIESPHYLOXML) $(SDITREES)