#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket;
use Net::RTP;
use File::Find::Rule;
use threads;
use FindBin qw/$RealBin/;
use lib("$RealBin");
use EOMLResponses;
our $librarypath;

sub main{
    open(DAT, 'config') || die("Could not find the configuration file\n");
    my @params = <DAT>;
    close(DAT);
    my $port;

    foreach (@params){
        if(/^Port:\ (\d*)$/){
            $port  = $1;
        }
        if(/^LibraryPath:\ (.*)$/){
            $librarypath = $1;
        }
    }
    $librarypath =~ s/\~/$ENV{HOME}/e; #Convert shell terminology
    if(! -d $librarypath){
        die("The Library path provided in config does not exist");
    }else{
        &startConnection($port);
    }
}

sub startConnection{
    my ($port) = @_;
    my $welcomesocket = new IO::Socket::INET(
        LocalPort => $port,
        Proto => 'tcp',
        Listen => '5',
        Reuse => 1,
    );
    die "Could not create socket: $!\n" unless $welcomesocket;
    print "Server ready on port: $port";

    while(1){
        my $connectionsocket = $welcomesocket->accept();

        # read packets from the established connection
        my $request = "";
        $connectionsocket->recv($request, 1024);

        my $response = &processRequest($request);
        $connectionsocket->send($response);

        #Notify client response has been send
        shutdown($connectionsocket, 1);
    }
    $welcomesocket->close();
}

sub processRequest{
    my @packetfields = split(/\Q\n/, shift);

    #Request Packet Layout
    #
    #0   TypeBits: 01 or 10 # Play - List
    #1   Artist:
    #2   Album:
    #3   Track:
    #4   ByteRange:

    my $typebits = shift @packetfields;
    my $artist = shift @packetfields;
    $artist =~ s/Artist:\ (.*?)$/$1/e;
    my $album = shift @packetfields;
    $album =~ s/Album:\ (.*)$/$1/e;
    my $track = shift @packetfields;
    $track =~ s/Track:\ (.*)$/$1/e;
    my $byterange = shift @packetfields;
    $byterange =~ s/ByteRange:\ (.*)$/$1/e;

    if($typebits =~ /01/){
        return &respondWithList($artist, $album, $track);
    }elsif($typebits =~ /10/){
        return &prepareForStream($artist, $album, $track, $byterange);
    }
}

sub respondWithList{
    my ($artist, $album, $track) = @_;
    if($artist eq ""){
        my @artists = File::Find::Rule->directory->maxdepth(1)->relative->in($librarypath."/");
        my $list = join "\n", @artists;
        return &QueryFound($artist, $album, $track, $list);
    }elsif($album eq ""){
        if(not File::Find::Rule->directory->in($librarypath."/$artist/")){
            return &QueryNotFound($artist, $album, $track);
        }
        my @albums = File::Find::Rule->directory->maxdepth(1)->relative->in($librarypath."/$artist/");
        my $list = join "\n", @albums;
        return &QueryFound($artist, $album, $track, $list);
    }elsif($track eq ""){
        if(not File::Find::Rule->directory->in($librarypath."/$artist/$album/")){
            return &QueryNotFound($artist, $album, $track);
        }
        my @tracks = File::Find::Rule->file()
        ->relative
        ->name('*.mp3','*.ogg','*.aac','*.flac')
        ->in($librarypath."/$artist/$album/");
        foreach (@tracks) {
            my $taginfo = "$librarypath/$artist/$album/$_";
            $taginfo =~ s/\ /\\\ /g;
            $taginfo = `taginfo $taginfo`;
            $taginfo =~ /.*TITLE=\"(.*?)\".*/;
            $_ = "$_ / $1";
        }

        my $list = join "\n", @tracks;
        return &QueryFound($artist, $album, $track, $list);
    }else{
        if(not File::Find::Rule->exists->in($librarypath."/$artist/$album/$track")){
            return &QueryNotFound($artist, $album, $track);
        }
        my $taginfo = "$librarypath/$artist/$album/$track";
        $taginfo =~ s/\ /\\\ /g;
        $taginfo = `taginfo $taginfo`;
        return &QueryFound($artist, $album, $track, $taginfo);
    }
}

sub prepareForStream{
    my ($artist, $album, $track, $byterange) = @_;
    if(not $artist || not $album || not $track){
        return &NotSpecificEnough();
    }
    if(not File::Find::Rule->exists->in($librarypath."/$artist/$album/$track")){
        return &QueryNotFound($artist, $album, $track);
    }
    my $streamsocket = new IO::Socket::INET(
        Proto=>'tcp',
        Listen=>'1',
        Reuse=>'1',
        LocalPort=>'0',
    );
    die "Could not create socket: $!\n" unless $streamsocket;
    print "Streaming on port: ",$streamsocket->sockport();
    my $streamthread = threads->create(\&streamMusic, $streamsocket, "$librarypath/$artist/$album/$track");
    $streamthread->detach();
    return &ReadyForTransmission($artist, $album, $track, $streamsocket->sockport());
}

sub streamMusic{
    my ($socket, $musicpath) = @_;
    my $streamer = $socket->accept();
    open(DAT, $musicpath);
    my @song = <DAT>;
    close(DAT);
    foreach  (@song) {
        $streamer->send($_);
    }
    #Notify client response has been send
    shutdown($streamer, 1);
}

&main();
