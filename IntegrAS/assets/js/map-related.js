var iconosDeMarcador = [];
var iconLength = 35;
var redes = []; 
var markerIcon = L.Icon.extend({
    options: {
        iconSize: [iconLength, iconLength],
        iconAnchor: [iconLength / 2, iconLength / 2],
        popupAnchor: [0, -10]
    }
});

function displaySideBar() {
    $("#side-bar").removeClass("hidden");
}

function hideSideBar() {
    $("#side-bar").addClass("hidden");
}

function cerrarContenedorDeGraficas() {
    $("#contenedorDeGraficas").css("display", "none");
}

$.getJSON("assets/data/metricas.json", function(data) {
    $.each(data, function(key, val) {
        val.icon = new markerIcon({ iconUrl: val.url });
        val.antenna = new markerIcon( {iconUrl: val.antenna} );
        val.popup = construirPopUp(key);
        iconosDeMarcador.push(val);
    });
});

function construirPopUp(nivel) {
    var metrica = iconosDeMarcador[nivel];
    var html = "";
    switch (nivel) {
        case 0:
            html = document.getElementById("good-q");
            break;
        case 1:
            html = document.getElementById("regular-q");
            break;
        case 2:
            html = document.getElementById("bad-q");
            break;
        case 3:
            html = document.getElementById("vbad-q");
            break;
        case 4:
            html = document.getElementById("extreme-q");
            break; 
        case 5:
            html = document.getElementById("unknown-q");
            break;     
        default:
            break;
    }    
    return html;
}

/*
let mymap = L.map('map-container', {zoomControl: false}).setView([22.2515678, -101.1115929], 6);
new L.Control.Zoom({ position: 'bottomleft' }).addTo(mymap);
*/

L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(mymap);

var estaciones = new L.FeatureGroup();

$.getJSON("assets/data/analysis.json", function(jsonData) {
    calcularRedes(jsonData).forEach(function(red) {
        marcador = generarMarcador(red);
        marcador.addTo(mymap);
        marcador.codigo = red.codigo;
        marcador.on("click", function(event) {
            var redSeleccionada = event.sourceTarget.codigo;
            configurarBarraLateral(redSeleccionada);
            configurarPopUp(redSeleccionada);
        });

        console.log(red.estaciones);
        red.estaciones.forEach(function(estacion) {
            var metrica = iconosDeMarcador[estacion.calidadDelAire - 1];
            var marcadorDeEstacion = L.marker([estacion.LAT, estacion.LNG], { icon: metrica.antenna });
        
            //marcador = generarMarcador(estacion);
            estaciones.addLayer(marcadorDeEstacion);
        });
    });
});

mymap.on("zoomend", function() {
    console.log(mymap.getZoom());
    if(mymap.getZoom() < 12){
        mymap.removeLayer(estaciones);
    } else {
       mymap.addLayer(estaciones); 
    }
});

function configurarBarraLateral(codigoDeRed) {

    if(!($("#side-bar").hasClass("hidden"))) {
        hideSideBar();
    }
    $("#side-bar > main > .contenedor").empty();
    
    var redSeleccionada = null;
    redes.forEach(function(redTemporal) {
        if(redTemporal.codigo == codigoDeRed) {
            redSeleccionada = redTemporal;
        }
    })

    var metrica = iconosDeMarcador[redSeleccionada.calidad - 1];

    $("#color-band").parent().children().css("background-color", metrica.hex);
    $(".indice-calidad > p > span").text(metrica.calidad);
    $(".nivel-riesgo > p > span").text(metrica.riesgo);
    $(".nombre-de-red > p > span").text(redSeleccionada.nombre);

    redSeleccionada.estaciones.forEach(function(estacion) {
        var content = crearComponenteDeEstacion(codigoDeRed, estacion.IDSTATION, iconosDeMarcador[estacion.calidadDelAire - 1].url, estacion.NAMESTATION);
        $("#side-bar > main > .contenedor").append(content);
    });
    displaySideBar();
}

function configurarPopUp(codigoDeRed) {
    var redSeleccionada = null;
    redes.forEach(function(redTemporal) {
        if(redTemporal.codigo == codigoDeRed) {
            redSeleccionada = redTemporal;
        }
    })
    var metrica = iconosDeMarcador[redSeleccionada.calidad - 1];
    $(".popup-color-band").css("background-color", metrica.hex);
} 

function crearComponenteDeEstacion(idRed, idEstacion, icono, nombre) {
    return '<div class="estacion" id-estacion="' + idEstacion + '" id-red="' + idRed + '" onclick="abrirGraficas(this)"><img class="icono" src="' + icono + '" /><p class="nombre">' + nombre + '</p></div>';
}

function calcularRedes(estaciones) {
    redesDeMonitoreo = {};
    //generalizando las estaciones de acuerdo a su red.
    estaciones.forEach(function(estacion){
        var codigoDeRed = estacion.CODE;
        if(codigoDeRed in redesDeMonitoreo){
            redesDeMonitoreo[codigoDeRed].estaciones.push(estacion);
        } else {
            redesDeMonitoreo[codigoDeRed] = {nombre:estacion.NAME,codigo: codigoDeRed,estaciones: [estacion]};
        }
    });
    redes = Object.keys(redesDeMonitoreo).map(i => redesDeMonitoreo[i]);

    //Calculamos la posición de la red de monitoreo...
    redes.forEach(function(red){
        var latitude = 0.0;
        var longitude = 0.0;
        var calidad = 0;
        red.estaciones.forEach(function(estacion){
            latitude += parseFloat(estacion.LAT);
            longitude += parseFloat(estacion.LNG);
            if(estacion["calidadDelAire"] > calidad && estacion["calidadDelAire"] < 6){
                calidad = estacion["calidadDelAire"];
            }
        });
        if(calidad == 0) calidad = 6;
        red.calidad = calidad;
        red.riesgo = calidad;
        red.latitude = latitude / red.estaciones.length;
        red.longitude= longitude / red.estaciones.length;
    });

    //Arreglo de redes (contienen las estaciones que le pertenecen).
    return redes;
}

function generarMarcador(red) {
    var marcador = iconosDeMarcador[red.calidad - 1];
    if (marcador != null) {
        console.log(marcador.popup);
        return L.marker([red.latitude, red.longitude], { icon: marcador.icon }).bindPopup(marcador.popup);
    } else {
        return null;
    }
}

function abrirGraficas(nodo){
  var idSeleccionado = nodo.getAttribute("id-estacion");
  window.open("estacionDeMonitoreo.html?id=" + idSeleccionado , '_blank');
}