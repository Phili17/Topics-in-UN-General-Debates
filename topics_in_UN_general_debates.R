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

terms(topicModel, 10)

# fuer die Topics Namen "bauen" in Uebung, fuer Arbeit nicht sinnvoll
#top5termsPerTopic <- terms(topicModel, 5)
#topicNames <- apply(top5termsPerTopic, 2, paste, collapse = " ")

# ich weiss nicht, ob es der richtige Weg ist, nur Bigramme zu vewenden!?!?!?!?
# -> Diskussion

# Visualisierung

# LDAvis browser analog zur Uebung:
library(LDAvis)
library("tsne")
svd_tsne <- function(x) tsne(svd(x)$u)
json <- createJSON(phi = beta, theta = theta, doc.length = rowSums(bigram_dfm),
                   vocab = colnames(bigram_dfm), term.frequency = colSums(bigram_dfm), mds.method = svd_tsne,
                   plot.opts = list(xlab = "", ylab = "")) 
serVis(json)
