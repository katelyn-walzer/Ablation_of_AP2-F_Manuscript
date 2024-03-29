# load packages ----
library(tidyverse) 
library(tximport)
library(biomaRt)

setwd("/Users/katelynwalzer/Desktop/RNA_Seq_Striepen/2021_Feb_AP2-F_Knockdown")
getwd()

# read in study design ----
targets <- read_tsv("Study_Design_AP2_F_DiCre_Feb_2021.txt")

# create file paths to the abundance files generated by Kallisto using the 'file.path' function
path <- file.path(targets$sample, "abundance.h5")

# check to make sure this path is correct by seeing if the files exist
all(file.exists(path)) 

# use dplyr to modify study design to include these file paths as a new column.
targets <- mutate(targets, path)

# import Kallisto transcript counts into R using Tximport ----
Txi_gene <- tximport(path, 
                     type = "kallisto", 
                     txOut = TRUE,
                     countsFromAbundance = "lengthScaledTPM")

#take a look at the type of object
class(Txi_gene)
names(Txi_gene)

myCPM <- as_tibble(Txi_gene$abundance, rownames = "geneSymbol") # counts after adjusting for transcript length
myCounts <- as_tibble(Txi_gene$counts, rownames = "geneSymbol") # counts per million (CPM) 

library(hrbrthemes) 
library(RColorBrewer) 
library(reshape2)
library(genefilter) 
library(edgeR) 
library(matrixStats)


# Identify variables of interest in study design file ----
targets
groups1 <- targets$strain_condition
groups1 <- factor(groups1)
sampleLabels <- targets$sample

# Examine data up to this point ----
myCPM <- Txi_gene$abundance
myCounts <- Txi_gene$counts

# graph both matrices 
colSums(myCPM)
colSums(myCounts)

# Take a look at the heteroskedasticity of the data ----
# first, calculate row means and standard deviations for each transcript or gene 
# and add these to the data matrix
myCPM.stats <- transform(myCPM, 
                         SD=rowSds(myCPM), 
                         AVG=rowMeans(myCPM),
                         MED=rowMedians(myCPM)
)

head(myCPM.stats)

#produce a scatter plot of the transformed data
ggplot(myCPM.stats, aes(x=SD, y=MED)) +
  geom_point(shape=16, size=2)


# Make a DGElist from the counts, and plot ----
myDGEList <- DGEList(Txi_gene$counts)


save(myDGEList, file = "myDGEList")


# use the 'cpm' function from EdgeR to get counts per million
cpm <- cpm(myDGEList) 
colSums(cpm)
log2.cpm <- cpm(myDGEList, log=TRUE)


# Take a look at the distribution of the Log2 CPM
nsamples <- ncol(log2.cpm)
# now select colors from a single palette
myColors <- brewer.pal(nsamples, "Paired")

# 'coerce' the data matrix to a dataframe to use tidyverse tools on it
log2.cpm.df <- as_tibble(log2.cpm)

colnames(log2.cpm.df) <- sampleLabels

# use the reshape2 package to 'melt' dataframe (from wide to tall)
log2.cpm.df.melt <- melt(log2.cpm.df)


ggplot(log2.cpm.df.melt, aes(x=variable, y=value, fill=variable)) +
  geom_violin(trim = FALSE, show.legend = FALSE) +
  stat_summary(fun.y = "median", geom = "point", shape = 124, size = 6, color = "black", show.legend = FALSE) +
  labs(y="log2 expression", x = "sample",
       title="Log2 Counts per Million (CPM)",
       subtitle="unfiltered, non-normalized",
       caption=paste0("produced on ", Sys.time())) + 
  coord_flip() 

# Filter the data ----
#first, take a look at how many genes or transcripts have no read counts at all
table(rowSums(myDGEList$counts==0)==12)

# set some cut-off to get rid of genes/transcripts with low counts
keepers <- rowSums(cpm>10)>=3 #last number is replicates, min replicates, at least expressed ten times
myDGEList.filtered <- myDGEList[keepers,]
dim(myDGEList.filtered)

log2.cpm.filtered <- cpm(myDGEList.filtered, log=TRUE)
log2.cpm.filtered.df <- as_tibble(log2.cpm.filtered) 
colnames(log2.cpm.filtered.df) <- sampleLabels
log2.cpm.filtered.df.melt <- melt(log2.cpm.filtered.df)

ggplot(log2.cpm.filtered.df.melt, aes(x=variable, y=value, fill=variable)) +
  geom_violin(trim = FALSE, show.legend = FALSE) +
  stat_summary(fun.y = "median", geom = "point", shape = 124, size = 6, color = "black", show.legend = FALSE) +
  labs(y="log2 expression", x = "sample",
       title="Log2 Counts per Million (CPM)",
       subtitle="filtered, non-normalized",
       caption=paste0("produced on ", Sys.time())) +
  coord_flip() 

# Normalize the data ----
myDGEList.filtered.norm <- calcNormFactors(myDGEList.filtered, method = "TMM")

# use the 'cpm' function from EdgeR to get counts per million from the normalized data
log2.cpm.filtered.norm <- cpm(myDGEList.filtered.norm, log=TRUE)
log2.cpm.filtered.norm.df <- as_tibble(log2.cpm.filtered.norm)
colnames(log2.cpm.filtered.norm.df) <- sampleLabels
log2.cpm.filtered.norm.df.melt <- melt(log2.cpm.filtered.norm.df)

ggplot(log2.cpm.filtered.norm.df.melt, aes(x=variable, y=value, fill=variable)) +
  geom_violin(trim = FALSE, show.legend = FALSE) +
  stat_summary(fun.y = "median", geom = "point", shape = 124, size = 6, color = "black", show.legend = FALSE) +
  labs(y="log2 expression", x = "sample",
       title="Log2 Counts per Million (CPM)",
       subtitle="filtered, TMM normalized",
       caption=paste0("produced on ", Sys.time())) +
  coord_flip() 

library(DT) 
library(gt) 
library(plotly) 
library(skimr)


# Need to convert the datamatrix to a dataframe, while preserving the rownames as a new column in the dataframe
mydata.df <- as_tibble(log2.cpm.filtered.norm, rownames = "geneSymbol")
colnames(mydata.df) <- c("geneSymbol", sampleLabels)
skim(mydata.df)
mydata.melt <- as_tibble(melt(mydata.df))

write_tsv(mydata.df, "normData_CryptoDB_AP2_F_Knockdown.txt") 
#This data was used for GSEA analysis using the Desktop Software GSEA 4.3.2
#Number of permutations is 1000
#Enrichment statistic weighted
#Metric for ranking genes Diff_of_Classes
#All other parameters kept as default

# Hierarchical clustering ---------------
distance <- dist(t(log2.cpm.filtered.norm), method="maximum") 
clusters <- hclust(distance, method = "complete") 
plot(clusters, labels=sampleLabels)


# Principal component analysis (PCA) -------------
pca.res <- prcomp(t(log2.cpm.filtered.norm), scale.=F, retx=T)
#look at pca.res in environment
ls(pca.res)
summary(pca.res) 
x <- pca.res$rotation 
pca.res$x
pc.var<-pca.res$sdev^2 
pc.per<-round(pc.var/sum(pc.var)*100, 1)
pc.per

# Visualize the PCA result ------------------
pca.res.df <- as_tibble(pca.res$x)
ggplot(pca.res.df, aes(x=PC1, y=PC2, color=targets$strain_condition)) +
  geom_point(size=8) +
  theme_bw() +
  xlab(paste0("PC1 (",pc.per[1],"%",")")) + 
  ylab(paste0("PC2 (",pc.per[2],"%",")")) +
  labs(title="PCA plot of strains and treatment groups") +
  theme(legend.title = element_blank()) +
  theme(axis.text=element_text(size = 14),
        axis.title = element_text(size=16),
        plot.title=element_text(face = "bold", size = 20),
        legend.text = element_text(size=16)) 

# Use dplyr 'mutate' function to add new columns based on existing data -------
mydata.df <- mutate(mydata.df,
                    WT_Ctrl.AVG = (WT_Ctrl_rep_1 + WT_Ctrl_rep_2 + WT_Ctrl_rep_3)/3,
                    WT_Rap.AVG = (WT_Rap_rep_1 + WT_Rap_rep_2 + WT_Rap_rep_3)/3,
                    AP2_F_Ctrl.AVG = (AP2_F_Ctrl_rep_1 + AP2_F_Ctrl_rep_2 + AP2_F_Ctrl_rep_3)/3,
                    AP2_F_Rap.AVG = (AP2_F_Rap_rep_1 + AP2_F_Rap_rep_2 + AP2_F_Rap_rep_3)/3,
                    
                    
                    LogFC.AP2F_rap_vs_AP2F_ctrl = (AP2_F_Rap.AVG - AP2_F_Ctrl.AVG),
                    LogFC.WT_rap_vs_WT_ctrl = (WT_Rap.AVG - WT_Ctrl.AVG),
                    LogFC.AP2F_ctrl_vs_WT_ctrl = (AP2_F_Ctrl.AVG - WT_Ctrl.AVG),
                    LogFC.AP2F_rap_vs_WT_rap = (AP2_F_Rap.AVG - WT_Rap.AVG)) %>%
  mutate_if(is.numeric, round, 2)


write_tsv(mydata.df,"2021_5_20_Diff_genes_avg_CryptoDB_50_AP2F_knockdown_DiCre.txt")


library(limma)

# Set up the design matrix ----
groups1 <- relevel(groups1, "AP2_F_rap")
design <- model.matrix(~0 + groups1)
colnames(design) <- levels(groups1)


# Model mean-variance trend and fit linear model to data ----
# Use VOOM function from Limma package to model the mean-variance relationship
v.DGEList.filtered.norm <- voom(myDGEList.filtered.norm, design, plot = TRUE)
# fit a linear model to your data
fit <- lmFit(v.DGEList.filtered.norm, design)


# Contrast matrix ----
# how do parasites respond to rapamycin treatment? What is the effect of the knockdown?
contrast.matrix <- makeContrasts(AP2F_rap_AP2F_ctrl = AP2_F_rap - AP2_F_control,
                                 WT_rap_WT_ctrl = WT_rap - WT_control,
                                 AP2F_ctrl_WT_ctrl = AP2_F_control - WT_control,
                                 AP2F_rap_WT_rap = AP2_F_rap - WT_rap,
                                 levels=design)


# extract the linear model fit -----
fits <- contrasts.fit(fit, contrast.matrix)
ebFit <- eBayes(fits)

# TopTable to view differentially expressed genes -----

#myTopHits is AP2_F rapamycin versus AP2_F control
myTopHits <- topTable(ebFit, adjust ="BH", coef=1, number=10000, sort.by="logFC")

# convert to a tibble
myTopHits <- as_tibble(myTopHits, rownames = "geneSymbol")

gt(myTopHits)


#myTopHits2 is WT rapamycin versus WT control
myTopHits2 <- topTable(ebFit, adjust ="BH", coef=2, number=10000, sort.by="logFC")

# convert to a tibble
myTopHits2 <- as_tibble(myTopHits2, rownames = "geneSymbol")

gt(myTopHits2)


#myTopHits3 is AP2_F ctrl versus WT control
myTopHits3 <- topTable(ebFit, adjust ="BH", coef=3, number=10000, sort.by="logFC")

# convert to a tibble
myTopHits3 <- as_tibble(myTopHits3, rownames = "geneSymbol")

gt(myTopHits3)


#myTopHits4 is AP2_F rapamycin versus WT rapamycin
myTopHits4 <- topTable(ebFit, adjust ="BH", coef=4, number=10000, sort.by="logFC")

# convert to a tibble
myTopHits4 <- as_tibble(myTopHits4, rownames = "geneSymbol")

gt(myTopHits4)


#Pull out genes from final LOPIT paper submission, column tagm.class.pam.pred.lab
crystalloid_body_LOPIT_submission_AP2_F <- subset(myTopHits,
                                                  geneSymbol=="cgd1_1510-RA" |
                                                    geneSymbol=="cgd2_2100-RA" |
                                                    geneSymbol=="cgd2_2110-RA" |
                                                    geneSymbol=="cgd2_790-RA" |
                                                    geneSymbol=="cgd6_313-RA" |
                                                    geneSymbol=="cgd6_820-RA" |
                                                    geneSymbol=="cgd7_1730-RA" |
                                                    geneSymbol=="cgd7_300-RA" |
                                                    geneSymbol=="cgd7_4810-RA" |
                                                    geneSymbol=="cgd7_5140-RA" |
                                                    geneSymbol=="cgd8_4290-RA" |
                                                    geneSymbol=="cgd8_4300-RA" |
                                                    geneSymbol=="cgd8_4310-RA" )


oocyst_wall_LOPIT_submission_AP2_F <- subset(myTopHits,
                                             geneSymbol== "cgd1_3550-RA" |
                                               geneSymbol== "cgd1_800-RA" |
                                               geneSymbol== "cgd2_1590-RA" |
                                               geneSymbol== "cgd2_2510-RA" |
                                               geneSymbol== "cgd2_3040-RA" |
                                               geneSymbol== "cgd2_4350-RA" |
                                               geneSymbol== "cgd2_850-RA" |
                                               geneSymbol== "cgd3_1540-RA" |
                                               geneSymbol== "cgd3_1860-RA" |
                                               geneSymbol== "cgd3_190-RA" |
                                               geneSymbol== "cgd3_3700-RA" |
                                               geneSymbol== "cgd4_3090-RA" |
                                               geneSymbol== "cgd4_500-RA" |
                                               geneSymbol== "cgd4_670-RA" |
                                               geneSymbol== "cgd5_3073-RA" |
                                               geneSymbol== "cgd6_1450-RA" |
                                               geneSymbol== "cgd6_200-RA" |
                                               geneSymbol== "cgd6_2090-RA" |
                                               geneSymbol== "cgd6_210-RA" |
                                               geneSymbol== "cgd6_2470-RA" |
                                               geneSymbol== "cgd6_2900-RA" |
                                               geneSymbol== "cgd6_2920-RA" |
                                               geneSymbol== "cgd6_3730-RA" |
                                               geneSymbol== "cgd6_4440-RA" |
                                               geneSymbol== "cgd6_4640-RA" |
                                               geneSymbol== "cgd6_4840-RA" |
                                               geneSymbol== "cgd6_670-RA" |
                                               geneSymbol== "cgd6_710-RA" |
                                               geneSymbol== "cgd7_180-RA" |
                                               geneSymbol== "cgd7_1800-RA" |
                                               geneSymbol== "cgd7_4310-RA" |
                                               geneSymbol== "cgd7_4560-RA" |
                                               geneSymbol== "cgd7_5150-RA" |
                                               geneSymbol== "cgd7_5400-RA" |
                                               geneSymbol== "cgd7_850-RA" |
                                               geneSymbol== "cgd8_2670-RA" |
                                               geneSymbol== "cgd8_3350-RA" |
                                               geneSymbol== "cgd8_3870-RA" |
                                               geneSymbol== "cgd8_4230-RA" |
                                               geneSymbol== "cgd8_4660-RA" |
                                               geneSymbol== "cgd8_4830-RA" |
                                               geneSymbol== "cgd8_5080-RA" |
                                               geneSymbol== "cgd8_5090-RA" |
                                               geneSymbol== "cgd8_620-RA")

crystalloid_body_LOPIT_submission_WT <- subset(myTopHits2,
                                               geneSymbol=="cgd1_1510-RA" |
                                                 geneSymbol=="cgd2_2100-RA" |
                                                 geneSymbol=="cgd2_2110-RA" |
                                                 geneSymbol=="cgd2_790-RA" |
                                                 geneSymbol=="cgd6_313-RA" |
                                                 geneSymbol=="cgd6_820-RA" |
                                                 geneSymbol=="cgd7_1730-RA" |
                                                 geneSymbol=="cgd7_300-RA" |
                                                 geneSymbol=="cgd7_4810-RA" |
                                                 geneSymbol=="cgd7_5140-RA" |
                                                 geneSymbol=="cgd8_4290-RA" |
                                                 geneSymbol=="cgd8_4300-RA" |
                                                 geneSymbol=="cgd8_4310-RA" )


oocyst_wall_LOPIT_submission_WT <- subset(myTopHits2,
                                          geneSymbol== "cgd1_3550-RA" |
                                            geneSymbol== "cgd1_800-RA" |
                                            geneSymbol== "cgd2_1590-RA" |
                                            geneSymbol== "cgd2_2510-RA" |
                                            geneSymbol== "cgd2_3040-RA" |
                                            geneSymbol== "cgd2_4350-RA" |
                                            geneSymbol== "cgd2_850-RA" |
                                            geneSymbol== "cgd3_1540-RA" |
                                            geneSymbol== "cgd3_1860-RA" |
                                            geneSymbol== "cgd3_190-RA" |
                                            geneSymbol== "cgd3_3700-RA" |
                                            geneSymbol== "cgd4_3090-RA" |
                                            geneSymbol== "cgd4_500-RA" |
                                            geneSymbol== "cgd4_670-RA" |
                                            geneSymbol== "cgd5_3073-RA" |
                                            geneSymbol== "cgd6_1450-RA" |
                                            geneSymbol== "cgd6_200-RA" |
                                            geneSymbol== "cgd6_2090-RA" |
                                            geneSymbol== "cgd6_210-RA" |
                                            geneSymbol== "cgd6_2470-RA" |
                                            geneSymbol== "cgd6_2900-RA" |
                                            geneSymbol== "cgd6_2920-RA" |
                                            geneSymbol== "cgd6_3730-RA" |
                                            geneSymbol== "cgd6_4440-RA" |
                                            geneSymbol== "cgd6_4640-RA" |
                                            geneSymbol== "cgd6_4840-RA" |
                                            geneSymbol== "cgd6_670-RA" |
                                            geneSymbol== "cgd6_710-RA" |
                                            geneSymbol== "cgd7_180-RA" |
                                            geneSymbol== "cgd7_1800-RA" |
                                            geneSymbol== "cgd7_4310-RA" |
                                            geneSymbol== "cgd7_4560-RA" |
                                            geneSymbol== "cgd7_5150-RA" |
                                            geneSymbol== "cgd7_5400-RA" |
                                            geneSymbol== "cgd7_850-RA" |
                                            geneSymbol== "cgd8_2670-RA" |
                                            geneSymbol== "cgd8_3350-RA" |
                                            geneSymbol== "cgd8_3870-RA" |
                                            geneSymbol== "cgd8_4230-RA" |
                                            geneSymbol== "cgd8_4660-RA" |
                                            geneSymbol== "cgd8_4830-RA" |
                                            geneSymbol== "cgd8_5080-RA" |
                                            geneSymbol== "cgd8_5090-RA" |
                                            geneSymbol== "cgd8_620-RA")


#Make a volcano plot for AP2-F DiCre untreated and treated
ggplot(myTopHits, aes(y=-log10(adj.P.Val), x=logFC, text = paste("Symbol:", geneSymbol))) + geom_point(size=4) +
  geom_point(mapping = NULL, oocyst_wall_LOPIT_submission_AP2_F, size = 4, colour = "mediumpurple2", inherit.aes = TRUE) +
  geom_point(mapping = NULL, crystalloid_body_LOPIT_submission_AP2_F, size = 4, colour = "magenta", inherit.aes = TRUE) +
  ylim(-0.5,10) +
  xlim(-4,4) +
  geom_hline(yintercept = -log10(0.01), linetype="dashed", colour="grey", size=0.5) +
  geom_hline(yintercept = -log10(0.05), linetype="dashed", colour="grey", size=1) +
  geom_vline(xintercept = 1, linetype="longdash", colour="grey", size=1) +
  geom_vline(xintercept = -1, linetype="longdash", colour="grey", size=1) +
  theme_bw() +
  theme(axis.text=element_text(size = 14),
        axis.title = element_text(size=16),
        plot.title=element_text(face = "bold", size = 20),
        plot.subtitle = element_text(size=16)) +
  labs(title="Effects of DiCre-mediated knockout of AP2-F") 

#Make a volcano plot for WT untreated and treated
ggplot(myTopHits2, aes(y=-log10(adj.P.Val), x=logFC, text = paste("Symbol:", geneSymbol))) +
  geom_point(size=4) +
  geom_point(mapping = NULL, oocyst_wall_LOPIT_submission_WT, size = 4, colour = "mediumpurple2", inherit.aes = TRUE) +
  geom_point(mapping = NULL, crystalloid_body_LOPIT_submission_WT, size = 4, colour = "magenta", inherit.aes = TRUE) +
  ylim(-0.5,10) +
  xlim(-4,4) +
  geom_hline(yintercept = -log10(0.01), linetype="dashed", colour="grey", size=0.5) +
  geom_hline(yintercept = -log10(0.05), linetype="dashed", colour="grey", size=1) +
  geom_vline(xintercept = 1, linetype="longdash", colour="grey", size=1) +
  geom_vline(xintercept = -1, linetype="longdash", colour="grey", size=1) +
  theme_bw() +
  theme(axis.text=element_text(size = 14),
        axis.title = element_text(size=16),
        plot.title=element_text(face = "bold", size = 20)) +
  labs(title="Effects of rapamycin treatment on wild type parasites")


# decideTests to pull out the DEGs and make Venn Diagram ----
results <- decideTests(ebFit, method="global", adjust.method="BH", p.value=0.01, lfc=1)

# take a look at what the results of decideTests looks like
head(results)
summary(results)
vennDiagram(results, include=c("up","down"))
vennDiagram(results, include="up")


# retrieve expression data for DEGs ----
head(v.DGEList.filtered.norm$E)
colnames(v.DGEList.filtered.norm$E) <- sampleLabels


#This gives all the DiffGenes, regardless of significance between samples (only needs to be significant in one)
diffGenes <- v.DGEList.filtered.norm$E[results[,1] !=0 | results[,2] !=0 | results[,3] !=0 | results[,4] !=0,]
head(diffGenes)
dim(diffGenes)
#convert DEGs to a dataframe using as_tibble
diffGenes.df <- as_tibble(diffGenes, rownames = "geneSymbol")


#Adding averages to Diff Genes
#This is where to make new files for gene expression log-fold changes
Differential_genes_avg.df <- mutate(diffGenes.df,
                                    WT_Ctrl.AVG = (WT_Ctrl_rep_1 + WT_Ctrl_rep_2 + WT_Ctrl_rep_3)/3,
                                    WT_Rap.AVG = (WT_Rap_rep_1 + WT_Rap_rep_2 + WT_Rap_rep_3)/3,
                                    AP2_F_Ctrl.AVG = (AP2_F_Ctrl_rep_1 + AP2_F_Ctrl_rep_2 + AP2_F_Ctrl_rep_3)/3,
                                    AP2_F_Rap.AVG = (AP2_F_Rap_rep_1 + AP2_F_Rap_rep_2 + AP2_F_Rap_rep_3)/3,
                                    
                                    
                                    #now make columns comparing each of the averages above 
                                    #do as rapamycin likely downregulates, so put control first
                                    
                                    LogFC.AP2F_rap_vs_AP2F_ctrl = (AP2_F_Rap.AVG - AP2_F_Ctrl.AVG),
                                    LogFC.WT_rap_vs_WT_ctrl = (WT_Rap.AVG - WT_Ctrl.AVG),
                                    LogFC.AP2F_ctrl_vs_WT_ctrl = (AP2_F_Ctrl.AVG - WT_Ctrl.AVG),
                                    LogFC.AP2F_rap_vs_WT_rap = (AP2_F_Rap.AVG - WT_Rap.AVG)) %>%
  mutate_if(is.numeric, round, 3)




#This is Supplemental File 1
write_tsv(Differential_genes_avg.df, "2021_5_20_Differential_genes_avg_CryptoDB_50_AP2F_knockdown_DiCre.txt")


#write DEGs to a file
write_tsv(diffGenes.df,"2021_5_20_DiffGenes_CryptoDB_50_LFC1.txt") 

#Check different ones, add as new spreadsheets to Supplemental File 1
#AP2F_rap_vs_AP2F_ctrl
diffGenes_AP2F <- v.DGEList.filtered.norm$E[results[,1] !=0,]
head(diffGenes_AP2F)
dim(diffGenes_AP2F)
#convert DEGs to a dataframe using as_tibble
diffGenes_AP2F.df <- as_tibble(diffGenes_AP2F, rownames = "geneSymbol")


Differential_genes_avg_AP2F.df <- mutate(diffGenes_AP2F.df,
                                         AP2_F_Ctrl.AVG = (AP2_F_Ctrl_rep_1 + AP2_F_Ctrl_rep_2 + AP2_F_Ctrl_rep_3)/3,
                                         AP2_F_Rap.AVG = (AP2_F_Rap_rep_1 + AP2_F_Rap_rep_2 + AP2_F_Rap_rep_3)/3,
                                         #now make columns comparing each of the averages above 
                                         LogFC.AP2F_rap_vs_AP2F_ctrl = (AP2_F_Rap.AVG - AP2_F_Ctrl.AVG)) %>%
  mutate_if(is.numeric, round, 3)


write_tsv(Differential_genes_avg_AP2F.df, "2021_5_20_Differential_genes_avg_AP2F_only_LFC1.txt")


#WT_rap_vs_WT_ctrl
diffGenes_WT <- v.DGEList.filtered.norm$E[results[,2] !=0,]
head(diffGenes_WT)
dim(diffGenes_WT)
#convert DEGs to a dataframe using as_tibble
diffGenes_WT.df <- as_tibble(diffGenes_WT, rownames = "geneSymbol")

#Error, only giving cgd2_4100 but no gene ID, no dims (not significant - adjusted p value just above 0.01)
Differential_genes_avg_WT.df <- mutate(diffGenes_WT.df,
                                       WT_Ctrl.AVG = (WT_Ctrl_rep_1 + WT_Ctrl_rep_2 + WT_Ctrl_rep_3)/3,
                                       WT_Rap.AVG = (WT_Rap_rep_1 + WT_Rap_rep_2 + WT_Rap_rep_3)/3,
                                       #now make columns comparing each of the averages above 
                                       LogFC.WT_rap_vs_WT_ctrl = (WT_Rap.AVG - WT_Ctrl.AVG)) %>%
  mutate_if(is.numeric, round, 3)


write_tsv(Differential_genes_avg_WT.df, "2021_5_20_Differential_genes_avg_WT_only_LFC1.txt")


#AP2F_ctrl_vs_WT_ctrl
diffGenes_ctrl <- v.DGEList.filtered.norm$E[results[,3] !=0,]
head(diffGenes_ctrl)
dim(diffGenes_ctrl)
#convert DEGs to a dataframe using as_tibble
diffGenes_ctrl.df <- as_tibble(diffGenes_ctrl, rownames = "geneSymbol")

Differential_genes_avg_ctrl.df <- mutate(diffGenes_ctrl.df,
                                         WT_Ctrl.AVG = (WT_Ctrl_rep_1 + WT_Ctrl_rep_2 + WT_Ctrl_rep_3)/3,
                                         AP2_F_Ctrl.AVG = (AP2_F_Ctrl_rep_1 + AP2_F_Ctrl_rep_2 + AP2_F_Ctrl_rep_3)/3,
                                         #now make columns comparing each of the averages above 
                                         LogFC.AP2F_ctrl_vs_WT_ctrl = (AP2_F_Ctrl.AVG - WT_Ctrl.AVG)) %>%
  mutate_if(is.numeric, round, 3)


write_tsv(Differential_genes_avg_ctrl.df, "2021_5_25_Differential_genes_avg_ctrl_only_LFC1.txt")


#AP2F_rap_vs_WT_rap
diffGenes_rap <- v.DGEList.filtered.norm$E[results[,4] !=0,]
head(diffGenes_rap)
dim(diffGenes_rap)
#convert DEGs to a dataframe using as_tibble
diffGenes_rap.df <- as_tibble(diffGenes_rap, rownames = "geneSymbol")

Differential_genes_avg_rap.df <- mutate(diffGenes_rap.df,
                                        WT_Rap.AVG = (WT_Rap_rep_1 + WT_Rap_rep_2 + WT_Rap_rep_3)/3,
                                        AP2_F_Rap.AVG = (AP2_F_Rap_rep_1 + AP2_F_Rap_rep_2 + AP2_F_Rap_rep_3)/3,
                                        #now make columns comparing each of the averages above 
                                        LogFC.AP2F_rap_vs_WT_rap = (AP2_F_Rap.AVG - WT_Rap.AVG)) %>%
  mutate_if(is.numeric, round, 3)


write_tsv(Differential_genes_avg_rap.df, "2021_5_25_Differential_genes_avg_rap_only_LFC1.txt")





