package dox.chrome;

import haxe.rtti.CType;
import chrome.Omnibox;
using StringTools;

class App implements IApp {
	
	static var API_DEF_REMOTE_PATH = "https://raw.github.com/tong/dox.chrome/master/";
	//static var API_DEF_REMOTE_PATH = "http://192.168.0.110/dox.chrome/";
	
	static var fs : FileSystem;
	static var api : haxe.rtti.XmlParser;
	static var traverser : Array<Array<SuggestResult>>;
	static var actualAPIVersion : String;
	
	public var docpath : String;
	public var maxSuggestions : Int;
	public var useHaxeOrgSearch : Bool;
	public var useGoogleCodeSearch : Bool;
	public var useGoogleDevelopmentSearch : Bool;
	public var useStackoverflowSearch : Bool;
	
	function new() {
		
	//	LocalStorage.clear(); return;
		
		var settings = Settings.load();
		if( settings == null ) {
			this.docpath = 'http://haxe.org/api/';
			this.maxSuggestions = 10;
			this.useHaxeOrgSearch = true;
			this.useGoogleCodeSearch = true;
			this.useGoogleDevelopmentSearch = true;
			this.useStackoverflowSearch = true;
			Settings.save( this );
		} else {
			this.docpath = settings.docpath;
			this.useHaxeOrgSearch = settings.useHaxeOrgSearch;
			this.maxSuggestions = settings.maxSuggestions;
			this.useGoogleCodeSearch = settings.useGoogleCodeSearch;
			this.useGoogleDevelopmentSearch = settings.useGoogleDevelopmentSearch;
			this.useStackoverflowSearch = settings.useStackoverflowSearch;
		}
		
		var needAPIUpdate = true;
		var myAPIVersion = LocalStorage.getItem( 'api_version' );
		actualAPIVersion = haxe.Http.requestUrl( API_DEF_REMOTE_PATH+"version" );
		if( myAPIVersion != null ) {
			trace( "Actual API version: "+actualAPIVersion +" : My API version"+ myAPIVersion );
			if( actualAPIVersion == myAPIVersion ) {
				needAPIUpdate = false;
			}
		}
		
		var me = this;
		untyped window.webkitRequestFileSystem( window.PERSISTENT, 10*1024*1024, function(fs){
			App.fs = fs;
			
			/*
			// remove file
			fs.root.getFile( 'api', {create:false}, function(fe) {
				fe.remove(function() {
					trace( 'File removed.' );
				});
			});
			*/
			
			if( needAPIUpdate ) {
				me.updateAPI();
				return;
			}
			
			//trace( 'Opened file system: '+fs.name );
			fs.root.getFile( "api", {},
				function(fe){
					
					trace("Already do have the API description");
					
					//TODO
					// already have api description, is it up to date ?
					// check here ...
					//if( haveActualAPI() ) {}
					
					fe.file(function(file){
						var r = new FileReader();
						r.onloadend = function(e) {
							var data = r.result;
							api = JSON.parse( r.result );
							me.run();
						}
						r.readAsText( file );
					});
					//trace("Loading it anyway .....");
					//me.updateAPI();
				},
				function(err:FileError){
					if( err.code == FileError.NOT_FOUND_ERR ) {
						trace( "Don't have a API description, load it" );
						me.updateAPI(); // don't have api description, so load it
					} else {
						trace( "??? unexpected error "+err.code );
					}
				}
			);
		});
	}
	
	public function updateAPI( ?cb : String->Void ) {
		trace( "Updating API ("+API_DEF_REMOTE_PATH+")");
		//TODO update the api in case we don't have one or if a newer (haxe version) is available
		var me = this;
		var data = haxe.Http.requestUrl( API_DEF_REMOTE_PATH+"haxe_api" );
		api = JSON.parse( data );
		trace( "API file loaded" );
		App.fs.root.getFile( 'api', {create:true}, function(fe:FileEntry) {
			fe.createWriter(function(fw) {
				fw.onwriteend = function(e) {
					trace( "API file written to local file system");
					me.run();
					if( cb != null ) cb( null );
				}
				fw.onerror = function(e) {
					trace( 'Failed to write into local file system: '+e.toString());
					//if( active ) { TODO }
					if( cb != null ) cb( e.toString() );
				}
				var bb = new BlobBuilder();
				bb.append( data );
				fw.write( bb.getBlob('text/plain') );
			});
		});
	}
	
	#if DEBUG
	public function log( v : Dynamic, ?inf : haxe.PosInfos ) { haxe.Log.trace( v, inf ); }
	#end
	
	function run() {
		
		trace( "Activting extension ..." );
		
		Omnibox.onInputStarted.addListener(
			function(){
				setDefaultSuggestion( "" );
			}
		);
		
		Omnibox.onInputCancelled.addListener(
			function() {
				trace( "Input cancelled" );
				setDefaultSuggestion( "" );
			}
		);
		
		setDefaultSuggestion( "" );
		
		Omnibox.onInputChanged.addListener(
			function(text,suggest) {
				
				setDefaultSuggestion( text );
				
				if( text == null )
		            return;
				var stripped_text = text.trim();
				if( stripped_text == null )
					return;
				if( stripped_text == "" ) {
					setDefaultSuggestion( "" );
					return;
				}
				
				var term = stripped_text.toLowerCase();
				var suggestions = new Array<SuggestResult>();
				traverser = new Array<Array<SuggestResult>>();
				for( i in 0... 4 ) traverser.push( new Array<SuggestResult>() );
				searchSuggestions( api.root, term );
				
				for( t in traverser ) {
					for( s in t ) {
						if( suggestions.length < maxSuggestions ) {
							suggestions.push( s );
						}
					}
				}
				
				if( stripped_text.length >= 2 ) {
					if( useHaxeOrgSearch ) {
						suggestions.push(
					 		{
					 			content : stripped_text+" [Haxe.org Search]",
					 			description : [ "Search for \" <match>", stripped_text, "</match> \" using <match><url>Haxe.org</url></match> - <url>http://haxe.org/wiki/search?s=", StringTools.urlEncode( stripped_text ), "</url>" ].join( '' )
					 		}
						);
					}
					if( useGoogleCodeSearch ) {
						suggestions.push(
					 		{
					 			content : stripped_text+" [Google Code Search]",
					 			description : [ "Search for \"<dim>haXe</dim> <match>", stripped_text, "</match> <dim>lang:haxe</dim>\" using <match><url>Google Code Search</url></match> - <url>http://www.google.com/codesearch?q=", StringTools.urlEncode( "haxe " + stripped_text + " lang:haxe"), "</url>" ].join( '' )
					 		}
						);
					}
					if( useGoogleDevelopmentSearch ) {
						suggestions.push(
					 		{
					 			content : stripped_text+" [Development and Coding Search]",
					 			description : [ "Search for \"<match>", stripped_text, "</match>\" using <match><url>Develoment and Coding Search</url></match> - <url>http://www.google.com/cse?cx=005154715738920500810:fmizctlroiw&amp;q=", StringTools.urlEncode( stripped_text ), "</url>" ].join( '' )
					 		}
						);
					}
					if( useStackoverflowSearch ) {
						suggestions.push(
					 		{
					 			content : stripped_text+" [Stackoverflow Search]",
					 			description : [ "Search for \"<match>", stripped_text, "</match>\" using <match><url>Stackoverflow Search</url></match> - <url>http://stackoverflow.com/search?q=", StringTools.urlEncode( "haxe "+stripped_text ), "</url>" ].join( '' )
					 		}
						);
					}
				}
				
				suggest( suggestions );
			}
		);
		
		Omnibox.onInputEntered.addListener(
			function(text) {
				//trace( "Input entered: '"+text+"'" );
				if( text == null ) {
					nav( docpath );
					return;
				}
				var stripped_text = text.trim();
				if( stripped_text == null ) {
					nav( "http://haxe.org/api" );
					return;
				}
				if( stripped_text.startsWith( "http://" ) || stripped_text.startsWith( "https://" ) ) {
					nav( stripped_text );
					return;
				}
				if( stripped_text.startsWith( "www." ) || stripped_text.endsWith( ".com" ) || stripped_text.endsWith( ".net" ) || stripped_text.endsWith( ".org" ) || stripped_text.endsWith( ".edu" ) ) {
		            nav( "http://"+stripped_text );
        		    return;
        		}
        		
        		var suffix = " [Haxe.org Search]";
        		if( stripped_text.endsWith( suffix ) ) {
        			var query = stripped_text.substr( 0, stripped_text.length - suffix.length ).trim();
        			nav( "http://haxe.org/wiki/search?s="+StringTools.urlEncode( query ) );
					return;
        		}
        		suffix = " [Google Code Search]";
        		if( stripped_text.endsWith( suffix ) ) {
					var query = stripped_text.substr( 0, stripped_text.length - suffix.length ).trim();
					//nav( "http://www.google.com/codesearch?q="+StringTools.urlEncode( "haxe "+newquery + " lang:haxe" ) ); // dows not work, google does not know lang:haxe
					nav( "http://www.google.com/codesearch?q="+StringTools.urlEncode( "haxe "+query ) );
					return;
				}
	        	suffix = " [Development and Coding Search]";
	        	if( stripped_text.endsWith( suffix ) ) {
	        		var query = stripped_text.substr( 0, stripped_text.length - suffix.length ).trim();
	        		nav( "http://www.google.com/cse?cx=005154715738920500810:fmizctlroiw&q=" + StringTools.urlEncode( query ) );
	        		return;
	        	}
				suffix = " [Stackoverflow Search]";
	        	if( stripped_text.endsWith( suffix ) ) {
	        		var query = stripped_text.substr( 0, stripped_text.length - suffix.length ).trim();
	        		nav( "http://stackoverflow.com/search?q="+StringTools.urlEncode( "haxe "+query )+"&submit=search" );
	        		return;
	        	}
			}
		);
		
		LocalStorage.setItem( 'api_version', actualAPIVersion );
		
		trace( "Extension active, use it!" );
	}
	
	function searchSuggestions( root : Array<TypeTree>, term : String ) {
		//trace( "SEARCH: "+term, "info" );
		for( tree in root ) {
			switch( tree ) {
			case TPackage(name,full,subs) :
				if( name.fastCodeAt(0) == 95 ) // "_"
					continue;
				var parts = full.split( "." );
				for( p in parts ) {
					if( p == term ) {
						traverser[3].push( {
							content : docpath + full.split( "." ).join( "/" ).toLowerCase(),
							description : full
						} );
					}
				}
				searchSuggestions( subs, term );
			case TTypedecl(t) :
				addTypeSuggestion( term, t );
			case TEnumdecl(e) :
				addTypeSuggestion( term, e );
			case TClassdecl(c) :
				if( !addTypeSuggestion( term, c ) ) {
					//trace("TODO search class fields/methods/..");
				}
			}
		}
	}
	
	function addTypeSuggestion( term : String, t : { path : String, doc : String }, level : Int = 0 ) : Bool {
		var name = getTypeName( t.path );
		return if( name.toLowerCase().startsWith( term ) ) {
			var path = t.path.split( "." ).join( "/" ).toLowerCase();
			if( path.startsWith( "flash" ) ) // hacking flash9 target path
				path = "flash9"+path.substr(5);
			var url = docpath + path;
			var description =  "<match>"+name+"</match>";
			if( t.path != name ) description += " ("+t.path+")";
			if( t.doc != null ) {
				var doc = t.doc.trim();
				if( doc.length > 64 ) doc = doc.substr( 0, 64 ).trim()+"...";
				description += " - "+doc;
			}
			description += " <url>("+url+")</url>";
			traverser[level].push( {
				content : url,
				description: description
			} );
			true;
		} else false;
	}
	
	static function getTypeName( s : String ) : String  {
		var i = s.lastIndexOf( "." );
		return ( i == -1 ) ? s : s.substr( i+1 );
	}
	
	static function setDefaultSuggestion( text : String ) {
		var desc = '<url><match>HaXe API Search</match></url>';
		if( text != null ) desc +=  " "+text;
		Omnibox.setDefaultSuggestion( { description : desc } );
	}
	
	static function nav( url : String ) {
		chrome.Tabs.getSelected( null, function(tab) { chrome.Tabs.update( tab.id, { url: url } ); });
	}
	
	static function init() : IApp {
		#if DEBUG
		if( haxe.Firebug.detect() ) haxe.Firebug.redirectTraces();	
		trace( "DOX.chrome" );
		#end
		return new App();
	}
	
}
