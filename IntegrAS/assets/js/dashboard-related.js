function parse_query_string(query) {
    var vars = query.split("&");
    var query_string = {};
    for (var i = 0; i < vars.length; i++) {
        var pair = vars[i].split("=");
        var key = decodeURIComponent(pair[0]);
        var value = decodeURIComponent(pair[1]);
        // If first entry with this name
        if (typeof query_string[key] === "undefined") {
            query_string[key] = decodeURIComponent(value);
            // If second entry with this name
        } else if (typeof query_string[key] === "string") {
            var arr = [query_string[key], decodeURIComponent(value)];
            query_string[key] = arr;
            // If third or later entry with this name
        } else {
            query_string[key].push(decodeURIComponent(value));
        }
    }
    return query_string;
}

procesarData();

var metricas = [{
    calidad: "Buena",
    riesgo: "Bajo"
}, {
    calidad: "Aceptable",
    riesgo: "Moderado"
}, {
    calidad: "Mala",
    riesgo: "Alto"
}, {
    calidad: "Muy Mala",
    riesgo: "Muy Alto"
}, {
    calidad: "Extremadamente Mala",
    riesgo: "Extremadamente Alto"
}, {
    calidad: "No Disponible",
    riesgo: "No Disponible"
}];

function procesarData() {
    $.getJSON("assets/data/analysis.json", function(data) {

    var query = window.location.search.substring(1);
    var estacion = parse_query_string(query).id;

    $.each(data, function(index, estacionTmp) {
        if (estacionTmp.IDSTATION == estacion) {
            $("#nombre-de-estacion > p > span").text(estacionTmp.NAMESTATION);
            $("#nombre-del-estado > p > span").text(estacionTmp.STATE);
            $("#indice-calidad > p > span").text(metricas[estacionTmp.calidadDelAire - 1].calidad);
            $("#nivel-riesgo > p > span").text(metricas[estacionTmp.calidadDelAire - 1].riesgo);
            $(estacionTmp.promMovil12PM10 != -1 ? $("#prom1").text(estacionTmp.promMovil12PM10) : $("#prom1").text("Sin datos"));
            $(estacionTmp["promMovil12PM2.5"] != -1 ? $("#prom2").text(estacionTmp["promMovil12PM2.5"]) : $("#prom2").text("Sin datos"));
            $(estacionTmp.promMovil24SO2 != -1 ? $("#prom3").text(estacionTmp.promMovil24SO2) : $("#prom3").text("Sin datos"));
            $(estacionTmp.promMovil8CO != -1 ? $("#prom4").text(estacionTmp.promMovil8CO) : $("#prom4").text("Sin datos"));
            $(estacionTmp.promMovil8O3 != -1 ? $("#prom5").text(estacionTmp.promMovil8O3) : $("#prom5").text("Sin datos"));
            $(estacionTmp.promHorariaO3 != -1 ? $("#prom6").text(estacionTmp.promHorariaO3) : $("#prom6").text("Sin datos"));
            $(estacionTmp.promHorariaNO2 != -1 ? $("#prom7").text(estacionTmp.promHorariaNO2) : $("#prom7").text("Sin datos"));
            $("#table-date").text("Datos obtenidos en: " + estacionTmp.now);
            graficarEstacion(estacionTmp, "grafica-pm10", "grafica-pm25", "grafica-o3", "grafica-no2", "grafica-so2");
            }
        });
    });
}

function graficarEstacion(estacion, contenedorPM10, contenedorPM25, contenedorO3, contenedorNO2, contenedorSO2) {
    if (estacion["PM10ch"].length > 0) {
        concentraciones = estacion["PM10ch"];
        promedioMovilHr = estacion["promMovil12PM10T"];
        graficarContaminante("PM10", "ug/m3", concentraciones, promedioMovilHr, contenedorPM10, estacion.startDate);
    } else
        $("#" + contenedorPM10).css("display", "none");

    if (estacion["PM2.5ch"].length > 0) {
        concentraciones = estacion["PM2.5ch"];
        promedioMovilHr = estacion["promMovil12PM2.5T"];
        graficarContaminante("PM2.5", "ug/m3", concentraciones, promedioMovilHr, contenedorPM25, estacion.startDate);
    } else
        $("#" + contenedorPM25).css("display", "none");

    if (estacion["O3ch"].length > 0) {
        concentraciones = estacion["O3ch"];
        promedioMovilHr = estacion["promMovil8O3T"];
        graficarContaminante("O3", "ppm", concentraciones, promedioMovilHr, contenedorO3, estacion.startDate);
    } else
        $("#" + contenedorO3).css("display", "none");

    if (estacion["SO2ch"].length > 0) {
        concentraciones = estacion["SO2ch"];
        promedioMovilHr = estacion["promMovil24SO2T"];
        graficarContaminante("SO2", "ppm", concentraciones, promedioMovilHr, contenedorSO2, estacion.startDate);
    } else
        $("#" + contenedorSO2).css("display", "none");

    if (estacion["NO2ch"].length > 0) {
        concentraciones = estacion["NO2ch"];
        graficarContaminante("NO2", "ppm", concentraciones, null, contenedorNO2, estacion.startDate);
    } else
        $("#" + contenedorNO2).css("display", "none");

}

function procesarDia(fecha, hora) {
    var mes = (fecha.getUTCMonth() + 1).toString();
    if(mes.length == 1) mes = "0" + mes;
    var dia = (fecha.getUTCDate()).toString();
    if(dia.length == 1) dia = "0" + dia;
    var date = mes + "/" + dia + "/" + fecha.getUTCFullYear() + "-" + hora ;
    return date;
}

function addDays(date, days) {
    console.log("agregando 1 día a => ", date);
    date.setDate(date.getDate() + days);
    return date;
}

function graficarContaminante(contaminante, unidad, concentraciones, promedioMovilPorHora, contenedor, fechaInicial) {
    var parseDate = d3.time.format("%m/%d/%Y-%H").parse;
    var horas = range(0, concentraciones.length);
    var fechaDeInicio = new Date(fechaInicial);
    var tmpHoras = 0;
    var data = new Array();

    for (var i = 0; i < concentraciones.length; i++) {
        var tmpData = {};
        tmpData.concentracion = parseFloat(concentraciones[i]);
        tmpData.hora = tmpHoras;
        tmpData.fecha = parseDate(procesarDia(fechaDeInicio, tmpHoras));
        if (promedioMovilPorHora != null)
            tmpData.promedio = promedioMovilPorHora[i];
        data.push(tmpData);
        tmpHoras++;
        if (tmpHoras == 24) {
            addDays(fechaDeInicio, 1);
            tmpHoras = 0;
        }
    }

    var width = $("body > .contenedor").width();

    // Set the dimensions of the canvas / graph
    var margin = { top: 40, right: 20, bottom: 30, left: 90 },
        width = width - margin.left - margin.right - 80,
        height = 300 - margin.top - margin.bottom;

    // Set the ranges
    var x = d3.time.scale().range([0, width]);
    //var x = d3.time.scale().range([0, width]);
    var y = d3.scale.linear().range([height, 10]);

    var xAxis = d3.svg.axis().scale(x)
        .orient("bottom")
        .ticks(d3.time.days)
        .tickSize(10, 0)
        .tickFormat(d3.time.format("%d %b"));


    var yAxis = d3.svg.axis().scale(y)
        .orient("left").ticks(8);

    // Define the line
    var valueline = d3.svg.line()
        //.interpolate("basis")
        .x(function(d) { return x(d.fecha); })
        .y(function(d) { return y(d.concentracion); });

    if (promedioMovilPorHora != null)
        var valueline2 = d3.svg.line()
            //.interpolate("basis")
            .x(function(d) { return x(d.fecha); })
            .y(function(d) { return y(d.promedio); });

    // Adds the svg canvas
    var svg = d3.select("#" + contenedor)
        .append("svg")
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform",
            "translate(" + margin.left + "," + margin.top + ")");

    x.domain(d3.extent(data, function(d) { return d.fecha; }));

    if (promedioMovilPorHora != null)
        y.domain([0, d3.max(data, function(d) { return Math.max(d.concentracion, d.promedio); })]);
    else
        y.domain([0, d3.max(data, function(d) { return d.concentracion; })]);

    if (promedioMovilPorHora != null)
        svg.append("path")
        .attr("class", "line")
        .attr('stroke', '#A9C6D2')     
        .attr("d", valueline2(data));

    svg.append("path")
        .attr("class", "line")
        .attr('stroke', 'rgb(255, 127, 14)')  
        .attr("d", valueline(data));

    svg.selectAll("dot")
        .data(data)
        .enter().append("circle")
        .attr("r", 3)
        .attr("cx", function(d) { return x(d.fecha); })
        .attr("cy", function(d) { return y(d.concentracion); })
        .attr("concentracion", function(d){ return d.concentracion})
        .attr("hora", function(d) { return d.hora; })
        .attr("unidad", function(d){ return unidad})
        //.attr("transform", "translate(25)")
        .style("fill", 'rgb(255, 127, 14)')
        .on("mouseover", mouseover)
        //.on("mousemove", mousemove)
        .on("mouseout", mouseout);

    // Add the X Axis
    svg.append("g")
        .attr("class", "x axis")
        .attr("transform", "translate(0," + height + ")")
        .call(xAxis);

    // Add the Y Axis
    svg.append("g")
        .attr("class", "y axis")
        .call(yAxis);

    svg.append("text")
        .attr("transform", "rotate(-90)")
        .attr("y", 0 - margin.left)
        .attr("x", 0 - (height / 2))
        .attr("dy", "1em")
        .style("text-anchor", "middle")
        .text("Concentración (" + unidad + ")");

    svg.append("text")
        .attr("x", (width / 2))
        .attr("y", 0 - (margin.top / 2))
        .attr("text-anchor", "middle")
        .style("font-size", "16px")
        .style("text-decoration", "underline")
        .text(contaminante);

    var div = d3.select("body").append("div")
        .attr("class", "tooltip")
        .style("display", "none")
	.style("width", "fit-content");

    function mouseover(elem) {
        
	div.style("display", "inline");
        div.text(elem.hora + "hr\n" + elem.concentracion)
            .style("left", (d3.event.pageX - 34) + "px")
            .style("top", (d3.event.pageY - 17) + "px");
    }

    var max = d3.max(data, function(d) { return d.hora; });

    function mousemove() {
        div.text(function(d, i) { return max })
            .style("left", (d3.event.pageX - 34) + "px")
            .style("top", (d3.event.pageY - 50) + "px");
    }


    function mouseout() {
        div.style("display", "none");
        div.text("");
    }

}

function range(start, end) {
    var ans = [];
    for (let i = start; i <= end; i++) {
        ans.push(i);
    }
    return ans;
}
