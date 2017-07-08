# A heavily customized VCL to support WordPress
# Some items of note:
# Supports https
# Supports admin cookies for wp-admin
# Caches everything
# Support for custom error html page
vcl 4.0;
import directors;
import std;

# Assumed 'wordpress' host, this can be docker servicename
backend default {
    .host = "127.0.0.1";
    .port = "8080";
}



acl purge {
    "localhost";
  	"your-ip"/24;
    
}


sub vcl_recv {
# Define the desktop device
  set req.http.X-Device = "WEB";

  if (req.http.User-Agent ~ "iP(hone|od)" || req.http.User-Agent ~ "Android" || req.http.User-Agent ~ "iPad") {
    # Define smartphones and tablets
    set req.http.X-Device = "MOBILE";
  }

  elseif (req.http.User-Agent ~ "SymbianOS" || req.http.User-Agent ~ "^BlackBerry" || req.http.User-Agent ~ "^SonyEricsson" || req.http.User-Agent ~ "^Nokia" ||
  req.http.User-Agent ~ "^SAMSUNG" || req.http.User-Agent ~ "^LG") {
    # Define every other mobile device
    set req.http.X-Device = "MOBILE";
  }


	# Only a single backend
        set req.backend_hint= default;

        # Setting http headers for backend
        set req.http.X-Forwarded-For = client.ip;
    	set req.http.X-Forwarded-Proto = "https";

    	# Unset headers that might cause us to cache duplicate infos
    	unset req.http.Accept-Language;
    	unset req.http.User-Agent;

	# The purge...no idea if this works
		  #std.syslog(180, "RECV: " + req.http.host + req.url);
		
		if (req.method == "PURGE") {
		#std.syslog(0, client.ip);  
		  if (!client.ip ~ purge) {
		      return(synth(405,"Not allowed."));
		    }
		   # return (purge);
	  	}
	  	if ( std.port(server.ip) == 6080) {

		set req.http.x-redir = "https://" + req.http.host + req.url;
                return (synth(750, "Moved permanently"));
        }
if (req.method == "PURGE") {

if (req.http.X-Purge-Method == "regex") {

ban("req.url ~ " + req.url + " &amp;&amp; req.http.host ~ " + req.http.host);

return (synth(200, "Banned."));

} else {

return (purge);

}
}

 		# drop cookies and params from static assets
	  	if (req.url ~ "\.(gif|jpg|jpeg|swf|ttf|css|js|flv|mp3|mp4|pdf|ico|png)(\?.*|)$") {
	    	unset req.http.cookie;
	    	set req.url = regsub(req.url, "\?.*$", "");
	  	}

		# drop tracking params
	  	if (req.url ~ "\?(utm_(campaign|medium|source|term)|adParams|client|cx|eid|fbid|feed|ref(id|src)?|v(er|iew))=") {
	    	set req.url = regsub(req.url, "\?.*$", "");
	  	}

		# pass wp-admin urls
   		if (req.url ~ "(wp-login|wp-admin)" || req.url ~ "preview=true" || req.url ~ "xmlrpc.php") {
    		return (pass);
  		}

		# pass wp-admin cookies
	  	if (req.http.cookie) {
		    if (req.http.cookie ~ "(wordpress_|wp-settings-)") {
	      		return(pass);
		    } else {
		      unset req.http.cookie;
		    }
	  	}
 }



sub vcl_backend_response {
 #    set beresp.ttl = 1h;
set beresp.ttl = 1h;


#std.syslog(0, beresp.ttl);
    # retry a few times if backend is down
    if (beresp.status == 503 && bereq.retries < 3 ) {
       return(retry);
 }

    if (bereq.http.Cookie ~ "(UserID|_session)") {
	# if we get a session cookie...caching is a no-go
        set beresp.http.X-Cacheable = "NO:Got Session";
        set beresp.uncacheable = true;
        return (deliver);

    } elsif (beresp.ttl <= 0s) {
        # Varnish determined the object was not cacheable
        set beresp.http.X-Cacheable = "NO:Not Cacheable";

    } elsif (beresp.http.set-cookie) {
        if (beresp.http.set-cookie ~ "pll_language"){
           # Varnish determined the object was cacheable
          set beresp.http.X-Cacheable = "YES";

          # Remove Expires from backend, it's not long enough
          unset beresp.http.expires;

          # Set the clients TTL on this object
          # Set how long Varnish will keep it
          set beresp.ttl = 1w;

          # marker for vcl_deliver to reset Age:
          set beresp.http.magicmarker = "1";

        }else{
          # You don't wish to cache content for logged in users
          set beresp.http.X-Cacheable = "NO:Set-Cookie";
          set beresp.uncacheable = true;
          return (deliver);

        }
        

    } elsif (beresp.http.Cache-Control ~ "private") {
        # You are respecting the Cache-Control=private header from the backend
        set beresp.http.X-Cacheable = "NO:Cache-Control=private";
        set beresp.uncacheable = true;
        return (deliver);

    } else {
        # Varnish determined the object was cacheable
        set beresp.http.X-Cacheable = "YES";

        # Remove Expires from backend, it's not long enough
  	    unset beresp.http.expires;

        # Set the clients TTL on this object
        set beresp.http.Cache-Control = "max-age=31536000";

        # Set how long Varnish will keep it
        set beresp.ttl = 1w;

        # marker for vcl_deliver to reset Age:
        set beresp.http.magicmarker = "1";
    }

	# unset cookies from backendresponse
	if (!(bereq.url ~ "(wp-login|wp-admin)"))  {
		set beresp.http.X-UnsetCookies = "TRUE";
    		unset beresp.http.set-cookie;
    		set beresp.ttl = 1h;
	}

	# long ttl for assets
  	if (bereq.url ~ "\.(gif|jpg|jpeg|swf|ttf|css|js|flv|mp3|mp4|pdf|ico|png)(\?.*|)$") {
	    set beresp.ttl = 365d;

}
 set beresp.grace = 1w;

}

sub vcl_hash {
 if ( req.http.X-Forwarded-Proto ) {
  if ( req.http.X-Device ~ "MOBILE" ) {
    hash_data( req.http.X-Forwarded-Proto + req.http.X-Device );
  }else{

    hash_data( req.http.X-Forwarded-Proto );
  }
}
   

}

sub vcl_backend_error {
      # display custom error page if backend down
      if (beresp.status == 503 && bereq.retries == 3) {
          synthetic(std.fileread("/etc/varnish/error503.html"));
          return(deliver);
       }
 }

sub vcl_synth {
    # redirect for http
    if (resp.status == 750) {
        set resp.status = 301;
        set resp.http.Location = req.http.x-redir;
        return(deliver);
    }
# display custom error page if backend down
    if (resp.status == 503) {
        synthetic(std.fileread("/etc/varnish/error503.html"));
        return(deliver);
     }
}


sub vcl_deliver {
    #std.syslog(0, resp.http.age);
	# oh noes backend is down
    if (resp.status == 503) {
        return(restart);
    }
    if (resp.http.magicmarker) {
       # Remove the magic marker
        unset resp.http.magicmarker;

       # By definition we have a fresh object
        #set resp.http.age = "0";
	#unset resp.http.age;
     }
   if (obj.hits > 0) {
     set resp.http.X-Cache = "HIT";
   } else {
     set resp.http.X-Cache = "MISS";
   }
   #unset resp.http.age;
   set resp.http.Access-Control-Allow-Origin = "*";
}
sub vcl_hit {
  if (req.method == "PURGE") {
    return(synth(200,"OK"));
  }
}

sub vcl_miss {
  if (req.method == "PURGE") {
    return(synth(404,"Not cached"));
  }
}