#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket;
use File::Find::Rule;
use threads;
use FindBin qw/$RealBin/;
use lib("$RealBin");
use EOMLResponses;
our $librarypath;

sub main{
    open(my $DAT, "<", 'config') || die("Could not find the configuration file\n");
    my @params = <$DAT>;
    close($DAT);
    my $port;

    foreach (@params){
        if(/^Port:\ (\d*)$/){
            $port  = $1;
        }
        if(/^LibraryPath:\ (.*)$/){
            $librarypath = $1;
        }
    }
    $librarypath =~ s/\~/$ENV{HOME}/e; #Converting typical ~ into /home/***/
    if(not -d $librarypath){
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
        Listen => '500', #Max 500 users
        Reuse => 1, #Free port after finishing
    );
    die "Could not create socket: $!\n" unless $welcomesocket;
    print "Server ready on port: $port\n";

    while(1){
        my $connectionsocket = $welcomesocket->accept(); #Wait for request
        my $responsethread = threads->create(\&processRequest, $connectionsocket); #Dispatch it to new thread
        $responsethread->detach(); #Let it run we don't care anymore we wait for next request
    }
    $welcomesocket->close();
}

sub processRequest{
    my ($connectionsocket) = @_;

    # read packets from the established connection
    my $request = "";
    $connectionsocket->recv($request, 1024);
    my @packetfields = split(/\n/, $request); #split string on the \n sign

    #Request Packet Layout
    #
    #0   TypeBits: 01 or 10 # List - Play
    #1   Artist:
    #2   Album:
    #3   Track:
    #4   ByteRange:

    my $typebits = shift @packetfields;
    my $artist = shift @packetfields;
    #Strip away any unnecessary text from the request
    $artist =~ s/Artist:\ (.*?)$/$1/e;
    my $album = shift @packetfields;
    $album =~ s/Album:\ (.*)$/$1/e;
    my $track = shift @packetfields;
    $track =~ s/Track:\ (.*)$/$1/e;
    my $byterange = shift @packetfields;
    $byterange =~ s/ByteRange:\ (.*)$/$1/e;

    if($typebits =~ /01/){
        $connectionsocket->send(&respondWithList($artist, $album, $track));
    }elsif($typebits =~ /10/){
        &streamMusicFile($connectionsocket, $artist, $album, $track, $byterange);
    }
    #Notify client response has been send
    shutdown($connectionsocket, 1);
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
        return &TrackInfo($artist, $album, $track, $taginfo);
    }
}

sub streamMusicFile{
    my ($socket, $artist, $album, $track, $byterange) = @_;
    if($artist eq "" || $album eq "" || $track eq ""){
        $socket->send(&NotSpecificEnough());
        return;
    }
    if(not File::Find::Rule->exists->in($librarypath."/$artist/$album/$track")){
        $socket->send(&QueryNotFound($artist, $album, $track));
        return;
    }
    #TODO: implement byterange
    open(my $DAT, "<", $librarypath."/$artist/$album/$track") || $socket->send($!);
    read($DAT, my $song, -s "$librarypath/$artist/$album/$track");
    close($DAT);
    $socket->send($song);
}

&main();
