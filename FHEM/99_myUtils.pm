##############################################
# $Id: myUtilsTemplate.pm 7570 2015-01-14 18:31:44Z rudolfkoenig $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.

package main;

use strict;
use warnings;
use POSIX;

sub
myUtils_Initialize($$)
{
  my ($hash) = @_;
}

###########################
# Versenden von PostMe Listen per Telegram
###########################
sub PostMeTelegram($$$) {
  my ($recipient, $subject, $text) = @_;
  my @items = split(",", $text);
  @items = sort(@items);
  
  fhem ("set fhemBot message \@".$recipient." $subject:\n - ".join("\n - ", @items));
  return;
}


#############################################################################
#
#  TelegramInlineKeyboard
#
#############################################################################
sub telegramRecognition($){
   my ($event)    = @_;
   my $querypeer      = ReadingsVal("fhemBot", "queryPeer", 0);
   my $msgpeer        = ReadingsVal("fhemBot", "msgPeer", 0);
   my $queryReplyMsgId= ReadingsVal("fhemBot", "queryReplyMsgId", 0);
   my $MsgId          = ReadingsVal("fhemBot", "MsgId", 0);
   my $menuMsgId      = ReadingsVal("fhemBot", "menuMsgId", $queryReplyMsgId);
   my $calldata       = ReadingsVal("fhemBot", "callData", "");
   my $tg;
   my $dp;
   my $dm;
   my $res;
   my $cmd;
   my $click;
   my ($cb1,$cb2,$cb1raw);
  
   my $postItDevice = "postme_Listen";
   my $state = "0"; # step control for a decision table
   my @postItListen;
   
   do {
	# B01 - state   	
	if ($state eq "0") {
		# A01 - identify all postIt lists
        	for (my $i = 1; $i <= ReadingsVal($postItDevice, "postmeCnt",0); $i++) {
   			push(@postItListen, ReadingsVal($postItDevice, sprintf("postme%02dName",$i),""));
   		}
   		@postItListen = sort(@postItListen) if(scalar @postItListen > 0);
		# A05 - state = 1
		$state = "1";	
	} elsif ($state eq "1") {
		if ( $event =~ /queryData\:\s(.*)/ ) {
			# prolog - B03
			($cb1,$cb2) = split(/ /,$1,2);
			# B03 - menuentry
			if ($cb1 eq "Hauptmenü") {
				# B04 - exists postit lists
				if (scalar @postItListen > 0) {
					# A03 - send menuentries for main menu - PS				
					fhem("set fhemBot queryInline \@$querypeer (PostIt) (Steuerung) Hauptmenü");
					# A05 - state - 2
					$state = "end";						
				} else {
					# A03 - send menuentries for main menu - S				
					fhem("set fhemBot queryInline \@$querypeer (Steuerung) Hauptmenü");				
					# A05 - state - 2					
					$state = "end";
				}					
			} elsif ($cb1 eq "PostIt") {
				# A05 - state - 2					
				$state = "end";			
			}		
		} elsif ( $event =~ /menuData\:\s*(.*)\s*(.*)/ ) {
			
		} 
	} else {
		$state = "end";
	} 
   } while ($state ne "end");

      
   Log 3, "Telegram Notification Bearbeitung $event";
    #-- Klick event from inline keyboard
   if( $event =~ /queryData\:\s(.*)/ ){
     ($cb1,$cb2) = split(/ /,$1,2);
     Log 3, "Telegram Notification Bearbeitung queryData $cb1 $cb2";
     #-- Level 0
     if( $cb1 eq "Hauptmenü"){
       fhem("set fhemBot queryInline \@$querypeer (PostIt) (Steuerung) Hauptmenü");   
     #-- Level 1
     }elsif( $cb1 eq "PostIt"){
       $menuMsgId = $queryReplyMsgId;
       fhem("setreading fhemBot menuMsgId $menuMsgId");
       #-- PostIt-Menü für nicht-klickbare Listen
       fhem("set fhemBot queryEditInline $menuMsgId \@$querypeer (Hauptmenü) (Einkauf) (Baumarkt) PostIt Listenverwaltung;");        
       
     }elsif( $cb1 eq "Steuerung"){
       $menuMsgId = $queryReplyMsgId;
       fhem("setreading fhemBot menuMsgId $menuMsgId");
     }elsif( $cb1 =~ /((Einkauf)|(Baumarkt)).*/ ){
         my $cb1raw = $cb1;
         Log 3, "Einkauf oder Baumarkt";
         if( $cb1 =~ /Einkauf.*/){
         $cb1 = "Einkauf";
         $tg  = 1;
         $dp  = "<hier Adressaten>";
         
       }elsif( $cb1 =~ /Baumarkt.*/){
         $cb1 = "Baumarktliste";
         $tg  = 2;
         $dp  = "\<hier Adressaten>";
         
        }
        Log 3, "cb1 ist $cb1";
         #-- Level 3 to delete an item
         if( $cb1raw =~ /.*item\d\d/ ){
           Log 3, "Item zum Entfernen $cb1raw";
           $cb2 = $cb1raw;
           $cb2 =~ s/^.*_//;
           fhem("set postme_Listen remove $cb1 $cb2");
           InternalTimer(gettimeofday()+1, "telegramRecognition","queryData: $cb1",0);
         }elsif( $cb1raw =~ /.*add/ ){
           Log 3, "Hinzufügen $cb1raw";
           fhem("set fhemBot msgForceReply \@$querypeer Eingabe hinzuzufügender Posten");
           fhem("setreading fhemBot prevCmd add $cb1");
         #-- Level 2 for clickable items
         }else{
           $res = PostMe_tgi("postme_Listen",$cb1);
           Log 3, "Liste: $cb1 : $res";  
           fhem("set fhemBot queryEditInline $menuMsgId \@$querypeer (Hauptmenü|PostIt|hinzufügen:".$cb1."_add) ".$res."\n Klicken zum Entfernen"); 
         }
     }
   }elsif( $event =~ /menuData\:\s*(.*)\s*(.*)/ ){
     my $cb1 = $1;
     my $cb2 = $2;
     Log 3, "Telegram Notification Bearbeitung menuData $cb1 $cb2";
     if( $cb1 eq "Hauptmenü"){
       fhem("set fhemBot queryInline \@$msgpeer (PostIt) (Steuerung) Hauptmenü");
     }
   #-- Process line from forced reply
   }elsif( $event =~ /msgReplyMsgId\:\s+(\d*)/ ){
     my $mn = $1;
     my $mo = ReadingsVal("fhemBot", "prevMsgId", 0)+1;
     my $prev = ReadingsVal("fhemBot","prevCmd","none");
     if( $prev =~ /((add)|(remove)).*/ ){
       fhem("set postme_Listen $prev ".ReadingsVal("fhemBot","msgText",""));
       fhem("setreading fhemBot prevCmd none");
       #-- redisplay the list - small delay
       $prev =~ s/((add)|(remove))\s*//;
       InternalTimer(gettimeofday()+1, "telegramRecognition","queryData: $prev",0);
     } 
   }

   
}

1;
