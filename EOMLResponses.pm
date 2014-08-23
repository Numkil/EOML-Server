#!/usr/bin/perl
package EOMLResponses;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT =
qw(
QueryNotFound
NotSpecificEnough
QueryFound
ReadyForTransmission
);

sub QueryNotFound{
    my ($artist, $album, $track) = @_;
    $album = " " unless $album;
    $track = " " unless $track;

    #Packet
    my $code300 = <<"END_300";
Code: 300 Query not found.
Artist: $artist
Album: $album
Track: $track
END_300

    return $code300;
}

sub NotSpecificEnough{

    #Packet
    my $code301 = <<"END_301";
Code: 301 Not specific enough, Artist-Album-Track required.
END_301

    return $code301;
}

sub QueryFound{
    my ($artist, $album, $track, $response) = @_;

    #Packet
    my $code200 = <<"END_200";
Code: 200 Query found.
Artist: $artist
Album: $album
Track: $track
Data:
$response
END_200

    return $code200;
}

#Decrepated at the moment. Might come back in different format
#sub ReadyForTransmission{
    #my ($artist, $album, $track, $port) = @_;

    ##Packet
    #my $code201 = <<"END_201";
#Code: 201 Ready for transmission.
#Artist: $artist
#Album: $album
#Track: $track
#Port: $port
#END_201

    #return $code201;
#}

sub TrackInfo{
    my ($artist, $album, $track, $tags) = @_;

    #Packet
    my $code202 = <<"END_202";
Code: 202 Track info.
Artist: $artist
Album: $album
Track: $track
Tags:
$tags
END_202

    return $code202;
}
1;
