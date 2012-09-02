function loadTradition( textid, textname, editable ) {
	selectedTextID = textid;
    // First insert the placeholder image and register an error handler
    $('#textinfo_load_status').empty();
    $('#stemma_graph').empty();
    $('#textinfo_waitbox').show();
    $('#textinfo_container').hide().ajaxError( 
    	function(event, jqXHR, ajaxSettings, thrownError) {
    	if( ajaxSettings.url.indexOf( 'textinfo' ) > -1 && ajaxSettings.type == 'GET'  ) {
			$('#textinfo_waitbox').hide();
			$('#textinfo_container').show();
			display_error( jqXHR, $("#textinfo_load_status") );
    	}
    });
    
    // Hide the functionality that is irrelevant
    if( editable ) {
    	$('#add_new_stemma').show();
    	$('#edit_current_stemma').show();
    	$('#edit_textinfo').show();
    } else {
    	$('#add_new_stemma').hide();
    	$('#edit_current_stemma').hide();
    	$('#edit_textinfo').hide();
    }

    // Then get and load the actual content.
    // TODO: scale #stemma_graph both horizontally and vertically
    // TODO: load svgs from SVG.Jquery (to make scaling react in Safari)
    $.getJSON( basepath + "/textinfo/" + textid, function (textdata) {
    	// Add the scalar data
    	selectedTextInfo = textdata;
    	load_textinfo();
     	// Add the stemma(ta) and set up the stexaminer button
    	stemmata = textdata.stemmata;
    	if( stemmata.length ) {
    		selectedStemmaID = 0;
    		load_stemma( selectedStemmaID, basepath );
    	}
    	// Set up the relationship mapper button
		$('#run_relater').attr( 'action', basepath + "/relation/" + textid );
	});
}

function load_textinfo() {
	$('#textinfo_waitbox').hide();
	$('#textinfo_load_status').empty();
	$('#textinfo_container').show();
	$('.texttitle').empty().append( selectedTextInfo.name );
	// Witnesses
	$('#witness_num').empty().append( selectedTextInfo.witnesses.size );
	$('#witness_list').empty().append( selectedTextInfo.witnesses.join( ', ' ) );
	// Who the owner is
	$('#owner_id').empty().append('no one');
	if( selectedTextInfo.owner ) {
		$('#owner_id').empty().append( selectedTextInfo.owner );
	}
	// Whether or not it is public
	$('#not_public').empty();
	if( selectedTextInfo['public'] == false ) {
		$('#not_public').append('NOT ');
	}
	// What language setting it has, if any
	$('#marked_language').empty().append('no language set');
	if( selectedTextInfo.language && selectedTextInfo.language != 'Default' ) {
		$('#marked_language').empty().append( selectedTextInfo.language );
	}
}	

function load_stemma( idx ) {
	if( idx > -1 ) {
		selectedStemmaID = idx;
		$('#stemma_graph').empty();
		$('#stemma_graph').append( stemmata[idx] );
		// Stexaminer submit action
		var stexpath = basepath + "/stexaminer/" + selectedTextID + "/" + idx;
		$('#run_stexaminer').attr( 'action', stexpath );
	}
}

function display_error( jqXHR, el ) {
	var errobj = jQuery.parseJSON( jqXHR.responseText );
	var msg;
	if( errobj ) {
		msg = "An error occurred: " + errobj.error;
	} else {
		msg = "An error occurred; perhaps the server went down?"
	}
	var msghtml = $('<span>').attr('class', 'error').text( msg );
	$(el).empty().append( msghtml ).show();
}