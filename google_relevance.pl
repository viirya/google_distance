
use REST::Google::Search;
use Data::Dumper;
use Lingua::EN::Keywords;
use Lingua::Stem qw(stem);
use Lingua::StopWords qw(getStopWords);
use AI::Categorizer::FeatureVector;


my %keywordset;
my %results;
my @queries = ($ARGV[0], $ARGV[1]);

REST::Google::Search->http_referer('http://example.com');

foreach $query (@queries) {
  print $query . "\n";
  my $res = REST::Google::Search->new(
        q => $query
  );

  die "response status failure" if $res->responseStatus != 200;

  my $data = $res->responseData;

  my $cursor = $data->cursor;

  printf "pages: %s\n", $cursor->pages;
  printf "current page index: %s\n", $cursor->currentPageIndex;
  printf "estimated result count: %s\n", $cursor->estimatedResultCount;
  
  #$results{$query} = \$data->results; 
  my @search_ret = $data->results;
  $results{$query} = \@search_ret;
  #foreach $r ($data->results) {
  #  print Dumper($r);
  #  push @{$results{$query}}, $r;
  #}
  #print Dumper(@{$results{$query}});
}

my $stemmer = Lingua::Stem->new(-locale => 'EN-US');
$stemmer->stem_caching({ -level => 2 });

my $stopwords = getStopWords('en');

foreach $query (@queries) {
  foreach my $r (@{$results{$query}}) {
    my $content = $r->content;
    my @keywords = keywords($content); 
    my @split_keywords;

    foreach $keyword (@keywords) {
      my @sub_keywords = split(/\s/, $keyword);
      push @split_keywords, @sub_keywords;  
    }
    for $i (0..scalar(@split_keywords)-1) {
      my $string = $split_keywords[$i];
      $string =~ s/^\s+//;
      $string =~ s/\s+$//;
      $split_keywords[$i] = $string if ($string =~ m/(\w*)/);
    }
    my @removed_stop_keywords = grep { !$stopwords->{$_} } @split_keywords;  
    my $stemmmed_keywords   = $stemmer->stem(@removed_stop_keywords);
    my $stemmmed_keywords   = \@removed_stop_keywords;

    print "keywords for " . $r->url . "\n";

    foreach $keyword (@{$stemmmed_keywords}) {
      next if ($keyword eq '' || ($keyword =~ m/(\d|!)/));
      print "keyword: $keyword\n"; 
      if (!defined $keywordset{$query}{$keyword}) {
        $keywordset{$query}{$keyword} = 1;
      }
      else {
        $keywordset{$query}{$keyword}++;
      }
    }
  }
}

foreach $query (@queries) {
  foreach $keyword (keys %{$keywordset{$query}}) {
    foreach $sec_query (@queries) {
      next if $sec_query eq $query;
      if (!defined $keywordset{$sec_query}{$keyword}) {
        $keywordset{$sec_query}{$keyword} = 0;
      }
      if ($keywordset{$query}{$keyword} == 0 && $keywordset{$sec_query}{$keyword} == 0) {
        undef $keywordset{$query}{$keyword};
        undef $keywordset{$sec_query}{$keyword};
      }
    }
  }
}

my @feature_vectors;

foreach $query (@queries) {
  #print Dumper(%{$keywordset{$query}});
  my $f = new AI::Categorizer::FeatureVector (features => $keywordset{$query});
  print "$_ feature length: " . $f->length . "\n";
  #$f->normalize;
  push @feature_vectors, $f;
}

my $vector_dot = $feature_vectors[0]->dot($feature_vectors[1]);

my $vector_abs1 = 0;
my $vector_abs2 = 0;
my $vector_norm = 0;

foreach $feature ($feature_vectors[0]->names) {
  $vector_abs1 += ($feature_vectors[0]->value($feature) ** 2);
}
foreach $feature ($feature_vectors[1]->names) {
  $vector_abs2 += ($feature_vectors[1]->value($feature) ** 2);
}
$vector_norm = sqrt($vector_abs1) * sqrt($vector_abs2);

my $cosine = $vector_dot / $vector_norm;

print "dot: $vector_dot, norm: $vector_norm, cosine: $cosine\n";

exit;

