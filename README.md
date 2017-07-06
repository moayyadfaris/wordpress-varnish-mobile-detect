# wordpress-varnish-mobile-detect
A vcl to server wordpress website with mobile detection

use the following function in your php

```php
function isMobileDevice(){
	if(isset($_SERVER['HTTP_X_VARNISH'])){
		if ($_SERVER['HTTP_X_DEVICE']=='MOBILE'){
			return true;
		}else{
			return false;
		}
	}else{
		$aMobileUA = array(
        '/iphone/i' => 'iPhone', 
        '/ipod/i' => 'iPod', 
        '/ipad/i' => 'iPad', 
        '/android/i' => 'Android', 
        '/blackberry/i' => 'BlackBerry', 
        '/webos/i' => 'Mobile'
    );

    //Return true if Mobile User Agent is detected
    foreach($aMobileUA as $sMobileKey => $sMobileOS){
        if(preg_match($sMobileKey, $_SERVER['HTTP_USER_AGENT'])){
            return true;
        }
    }
    //Otherwise return false..  
    return false;
	}

    
}
```
