# Topics in UN General debates

options(stringsAsFactors = FALSE) 
library(quanteda) 
library(quanteda.textstats)
library(tidyverse)
library(dplyr)
require(topicmodels)

## Preprocessing
# Da sich die Korpusdateien in einer Struktur mit einem Ordner pro Jahr und 
# jeweils eine Datei pro Land befinden, muessen die Metadaten (Session, Jahr, Land) extrahiert werden.

# In einem DataFrame werden die Dateipfade, welche die Metadaten enthalten, verwaltet
file_paths <- list.files(path = "./dataverse_files/UN General Debate Corpus/TXT/", 
                         pattern = "\\.txt$", 
                         recursive = TRUE, 
                         full.names = TRUE)
data_frame <- tibble(filepath = file_paths) %>% 
  mutate( #dplyr library
    # Session (Sitzungsperiode), Jahr, Land und Rede extrahieren
    session = str_extract(filepath, "\\d{2}"),
    year = str_extract(filepath, "\\d{4}"),
    country = str_extract(basename(filepath), "^[A-Z]{3}"),
    speech = map_chr(filepath, ~ read_file(.x)),
  ) %>%
  # Filepath-Spalte nicht mehr benoetigt
  select(session, year, country, speech)

doc_names <- paste0(data_frame$year, data_frame$country)
ungd_corpus <- corpus(data_frame$speech, docnames = doc_names) #quanteda


# Lemma-Woerterbuch und stopword list lesen
lemma_data <- read.csv("./baseform_en.tsv", encoding = "UTF-8")
stopwords_extended <- readLines("./stopwords_en.txt", encoding = "UTF-8")

# Tokenisierung #quanteda library
corpus_tokens <- ungd_corpus %>%
  tokens(remove_punct = TRUE, remove_numbers = TRUE, remove_symbols = TRUE) %>%
  tokens_tolower() %>%
  tokens_remove(pattern = stopwords_extended, padding = T) %>%
  tokens_replace(lemma_data$inflected_form, lemma_data$lemma, valuetype = "fixed")
  

# Die Kollokationen einfach wie in der Uebung zu bilden ist hier nicht moeglich, da das Korpus viel zu gross ist
#ungd_collocations <- quanteda.textstats::textstat_collocations(corpus_tokens, min_count = 25)
#ungd_collocations <- ungd_collocations[1:250, ]
#corpus_tokens <- tokens_compound(corpus_tokens, ungd_collocations)
# -> Loesung: ngram-Erstellung; oder Kollokationen bilden auf Stichprobe (10% des Korpus)

# ngrams
ungd_bigrams <- tokens_ngrams(corpus_tokens, n = 2)

# Dokument-Term-Matrix / document-feature matrix
bigram_dfm <- ungd_bigrams %>%
  tokens_remove("") %>%
  dfm() %>%
  dfm_trim(min_docfreq = 3)
dim(bigram_dfm)

top_phrases <- topfeatures(bigram_dfm, n = 250) 
head(top_phrases, 40)
top5_phrases <- c("unite_nation", "general_assembly", "international_community", "develop_country",
                  "security_council")
bigram_dfm <- bigram_dfm[, !(colnames(bigram_dfm) %in% top5_phrases)]

# aus uebung:
# due to vocabulary pruning, we have empty rows in our DTM # LDA does not like this. So we remove those docs from the # DTM and the metadata
#sel_idx <- rowSums(DTM) > 0
#DTM <- DTM[sel_idx, ]
#textdata <- textdata[sel_idx, ]

sel_idx <- rowSums(bigram_dfm) > 0
bigram_dfm <- bigram_dfm[sel_idx, ]
data_frame <- data_frame[sel_idx, ]


# topic modelling
K <- 20 # Anzahl Topics
topicModel <- LDA(bigram_dfm, K, method = "Gibbs", control = list(
  iter = 500,
  seed = 1,
  verbose = 25,
  alpha = 0.02
))
tmResult <- posterior(topicModel)
attributes(tmResult)
beta <- tmResult$terms
theta <- tmResult$topics

terme <- terms(topicModel, 10)

# manuelle Zuweisung von Namen fuer jedes Topic (per Google Gemini 3.1 Pro kreiert)
topicNames <- c("Globale Brennpunkte der Blockfreien-Rhetorik",
                "Lateinamerika: Interventionismus und Menschenrechte",
                "Geteilte Staaten und Territorialkonflikte",
                "Nukleare Abrüstung im Ost-West-Konflikt",
                "Nord-Süd-Konflikt und postkoloniale Rohstoffökonomie",
                "Post-Sowjetischer Raum und Internationaler Terrorismus",
                "Polykrise: Klimawandel, SDGs und COVID-19",
                "Neue Weltwirtschaftsordnung (NIEO) und Blockfreiheit",
                "Afrikanische Dekolonisierung",
                "SIDS (Small Island Developing States) und Klimavulnerabilität",
                "UN-Gründung und die frühe Nachkriegsordnung",
                "Afrika in der Annan-Ära: Peacekeeping und HIV/AIDS",
                "Nahostkonflikt und Palästina-Frage",
                "Südostasiatische Konflikte & ASEAN",
                "Liberaler Institutionalismus und Multilateralismus",
                "Rüstungswettlauf und das geteilte Deutschland",
                "Militarisierung und Großmachtrivalität",
                "'Neue Weltordnung' und Boutros-Ghali-Ära",
                "Krisengebiete in West- und Zentralafrika",
                "Von den MDGs zu den SDGs")

# ich weiss nicht, ob es der richtige Weg ist, nur Bigramme zu vewenden!?!?!?!?
# -> Diskussion

## Visualisierung

# LDAvis browser analog zur Uebung:
library(LDAvis)
library("tsne")
svd_tsne <- function(x) tsne(svd(x)$u)
json <- createJSON(phi = beta, theta = theta, doc.length = rowSums(bigram_dfm),
                   vocab = colnames(bigram_dfm), term.frequency = colSums(bigram_dfm), mds.method = svd_tsne,
                   plot.opts = list(xlab = "", ylab = "")) 
serVis(json)


# Topic proportions over time analog zur Uebung:
library(reshape2)
library(ggplot2)
library(pals)
# append decade information for aggregation 
data_frame$decade <- paste0(substr(data_frame$year, 0, 3), "0")
# get mean topic proportions per decade 
topic_proportion_per_decade <- aggregate(theta,
                                         by = list(decade = data_frame$decade), mean)
# set topic names to aggregated columns
colnames(topic_proportion_per_decade)[2:(K+1)] <- topicNames
# reshape data frame
vizDataFrame <- melt(topic_proportion_per_decade, id.vars = "decade")
# plot topic proportions per deacde as bar plot
require(pals)

ggplot(vizDataFrame,
       aes(x=decade, y=value, fill=variable)) +
  geom_bar(stat = "identity") + ylab("proportion") + 
  scale_fill_manual(values = paste0(alphabet(20), "FF"), name = "decade") + 
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

# nochmal Visualisierung, aber zu einem Meta-Thema zusammengehoerige Topics sind in einer Farbe dargestellt

vizDataFrame <- vizDataFrame %>%
  mutate(
    meta_theme = case_when(
      variable %in% topicNames[c(5,8,11,15)] ~ "strukturelle Themen",
      variable %in% topicNames[c(4,16,17,18)] ~ "Kalter Krieg",
      variable %in% topicNames[c(1,2,3,6,9,12,13,14,19)] ~ "regionale Konflikte",
      variable %in% topicNames[c(7,10,20)] ~ "aktuelle globale Herausforderungen",
      TRUE ~ "Sonstige"
    )
  )

ggplot(vizDataFrame, 
       aes(x=decade, y=value, fill=meta_theme, group=variable)) + 
  geom_bar(stat="identity", color="white", linewidth=0.2) +
  ylab("proportion") +
  xlab("decade") +
  scale_fill_brewer(palette = "Set1", name = "Meta-Themen") +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1))
  




