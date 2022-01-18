import JSON
import Dates
using  HTTP


#= - - - - - - - Global variables - - - - - - - - - =#

# Criteria pollutants
criteriaPollutants = ["CO", "NO2", "O3", "SO2", "PM10", "PM2.5"]

# Request data starting from spacific date  (YYYY-MM-DD) and time window 
# 1 => day, 2 => 1 week, 3 => 2 weeks, 4 => month
startDate = string(Dates.today()- Dates.Day(12)); 
timeWindow = 3

# NORM data
airQuality = ["Buena", "Aceptable", "Mala", "Muy Mala", "Extremadamente Mala", "No disponible"]
riskLevel = ["Bajo", "Moderado", "Alto", "Muy Alto ", "Extremadamente Alto", "No disponible"]
PM10L = Dict("Buena"=>50., "Aceptable"=> 75., "Mala"=>155., "Muy Mala"=> 235., "Extremadamente Mala"=>235.)
PM25L = Dict("Buena"=>25., "Aceptable"=> 45., "Mala"=>79., "Muy Mala"=> 147., "Extremadamente Mala"=>147.)
O3LH= Dict("Buena"=>.051, "Aceptable"=> .095, "Mala"=>.135, "Muy Mala"=> .175, "Extremadamente Mala"=>.175)
O3LM= Dict("Buena"=>.051, "Aceptable"=> .07, "Mala"=>.092, "Muy Mala"=> .114, "Extremadamente Mala"=>.114)
NO2L= Dict("Buena"=>.107, "Aceptable"=> .210, "Mala"=>.230, "Muy Mala"=> .175, "Extremadamente Mala"=>.250)
SO2L= Dict("Buena"=>.008, "Aceptable"=> .110, "Mala"=>.165, "Muy Mala"=> .220, "Extremadamente Mala"=>.220)
COL = Dict("Buena"=>8.75, "Aceptable"=> 11.00, "Mala"=>13.00, "Muy Mala"=> 15.00, "Extremadamente Mala"=>15.00)



#= - - - - - - - Data retrievalfunctions - - - - - - - - - =#

function logEvent(code, message)
    println("[", Dates.now(), "]", " ", code, " => ", message)
end

#=
	Extrae contenido textual dentro de una cadena de caracteres,
	tomando como límites un conjunto de caracteres (startsWith)
	y un salto de línea (\n)
=#
function extractDataContent(text, startsWith)
	lines = split(text, "\n")
	for rawLine in lines
		line = strip(rawLine)
		if startswith(line, startsWith)
			data = line[length(startsWith)+1:end-1]
			# Esta línea crea un archivo de texto con el contenido encontrado
			return data
		end
	end
end

#=
	Escribe un archivo que con un determinado contenido textual
=#
function writeFile(text)
  logEvent("PROCESS", "Writing JSON from WebScrapping")
	io = open("output.json", "w+");
	write(io, text);
	close(io)
  logEvent("PROCESS", "Finished writing.")
end

#=
	Procesa el primer nivel (estados de Mx) de los datos obtenidos
	de SINAICA. Es importante notar que algunos estados están 
	divididos, como el caso de Chihuahua.
=#
function processStates(state)
	currentState = Dict()
	currentState["ID"] = state[1]
	currentState["NOMBRE"] = state[2]["nom"]
	currentState["CODIGO"] = state[2]["cod"]
	
  logEvent("PROCESS", string("Processing server data for state [", currentState["NOMBRE"] , "]"))

	# Hay un campo en los datos que se llama "cumple", pero no sé para que es...
	#currentState["CUMPLE"] = state[2]["cumple"]

	currentState["GPS"] = Dict("LAT" => state[2]["lat"], "LNG" => state[2]["long"])
	currentState["REDES"] = processNetworks(state[2]["redes"])
	return currentState
end

#=
	Realiza el procesamiento de las redes de estaciones que cada estado
	tiene. Este es el segundo nivel.
=#
function processNetworks(networks)
	networksList = []
	for network in networks
		currentNetwork = Dict()
		currentNetwork["ID"] = network[1]
		currentNetwork["NOMBRE"] = network[2]["nom"]
		currentNetwork["CODIGO"] = network[2]["cod"]
		currentNetwork["ESTACIONES"] = processStations(network[2]["ests"])

		# Hay un campo en los datos que se llama "cumple", pero no sé para que es...
		#currentNetwork["CUMPLE"] = network[2]["cumple"]

		push!(networksList, currentNetwork)
	end
	return networksList
end

#=
	Procesa los datos de las estaciones pertenecientes a una determinada red
=#
function processStations(stations)
	stationsList = []
	for station in stations
		currentStation = Dict()
		currentStation["ID"] = station[1]
		currentStation["NOMBRE"] = station[2]["nom"]
		currentStation["CODIGO"] = station[2]["cod"]
		currentStation["GPS"] = Dict("LAT" => station[2]["lat"], "LNG" => station[2]["long"])
		
		currentStation["CONTAMINANTES"] = getCriteriaPollutants(station[1])

		push!(stationsList, currentStation)
	end
	return stationsList
end

#=
	Obtiene los datos de los contaminantes criterios de una determinada estación
=#
function getCriteriaPollutants(stationID)
  url = "https://sinaica.inecc.gob.mx/pags/datGrafs.php"
  pollutantsData = Dict()
  for pollutant in criteriaPollutants
    params = Dict("estacionId" => stationID,
      "param" => pollutant,
      "fechaIni" => startDate,
      "rango" => timeWindow,
      "tipoDatos" => " ")
    dataLine = ""
    try
      response = HTTP.request("POST", url, ["Content-Type" => "application/x-www-form-urlencoded", "charset" => "UTF-8"], HTTP.URIs.escapeuri(params))
      logEvent("PROCESS", string("Processing server data for station [", stationID , "]"))
      dataLine = extractDataContent(String(response.body), "var dat = ")
    catch exception
      dataLine = string("{\"ERROR\":\"DATA_NOT_AVAILABLE\",\"DETAILS\": \"Data was not available\", \"LOG\":\"", exception, "\"}")
      errorMessage = string("Cannot access station data[", stationID,"]")
      logEvent("ERROR", errorMessage)
    end
    data = JSON.parse(dataLine)
    pollutantsData[pollutant] = data
  end
  return pollutantsData
end


#= ------------  Retrieve data -------------- =#

function retrieveData()
  generalDataURL = "https://sinaica.inecc.gob.mx/index.php"
  try
    logEvent("PROCESS", string("Retrieving data (", startDate,")"))
    response = HTTP.request("GET", generalDataURL)

    logEvent("PROCESS", string("Processing server data"))

    generalDataJSON = extractDataContent(String(response.body), "var cump = ")
    generalData = JSON.parse(generalDataJSON)
    data = []
    for state in generalData
      if !isnothing(tryparse(Float64,state[1]))
        push!(data, processStates(state))
      end
    end
    writeFile(JSON.json(data))
  catch exception
    errorMessage = "Cannot access SINAICA server"
    logEvent("ERROR", errorMessage)
  end
end

#= ------------  Data analysis -------------- =#


#=
	Read data file
=#
function readDataFile()
	io = open("output.json", "r");
	text = read(io, String);
	data = JSON.parse(text);
	close(io);
	return data;
end

function writeAnalysisFile(data)
	io = open("analysis.json", "w+");
	text = JSON.json(data)
	write(io, text);
	close(io)
end

function writeTS(fname, x, y)
  file = open(fname, "w+")
  #print(length(y), "   ", length(x))
  for i = 1 : length(x)
    println(file, x[i],  " ", y[i])
  end   
  close(file)
end

#=
FilterConcentrations
=#

function FilterConcentrations(data)
  for i = 1: length(data)
    if data[i] < 0
      data[i] = 0;
    elseif data[i] > 890 #arbitrary
      data[i] = 0;
    end  
  end
end

#=
checkMissingValues
=#
function checkMissingValues(data, hours, h)
  hr = 0;
  i = 1;
  k = length(hours)
  while i <= k
     if hours[i] != hr
      insert!(hours,i,hr)
      insert!(data,i,0)
      k = length(hours)
    end   
    if hr == h
      hr = 0
    else
      hr = hr+1;
    end 
    i = i+1   
  end
end

#=
Hist CA
=#
function histCA(con, level)
  calidad = [0 0 0 0 0 0]
  for i = 1 : length(con)
    if con[i] == 0
      calidad[6] = calidad[6] + 1
    elseif con[i] < level["Buena"]
      calidad[1] = calidad[1] + 1
    elseif con[i] >= level["Buena"] && con[i] < level["Aceptable"]
      calidad[2] = calidad[2] + 1
    elseif con[i] >= level["Aceptable"] &&  con[i] < level["Mala"]
      calidad[3] = calidad[3] + 1
    elseif con[i] >= level["Mala"] && con[i] <  level["Muy Mala"]
      calidad[4] = calidad[4] + 1
    else #= extremadamente mala =#
      calidad[5] = calidad[5] + 1
    end  
  end
  return calidad;
end

#=
Calidad del Aire: CA
=#
function CA(con, level)
  calidad = 0
  if con < level["Buena"]
    calidad = 1
  elseif con >= level["Buena"] && con < level["Aceptable"]
    calidad = 2
  elseif con >= level["Aceptable"] &&  con < level["Mala"]
    calidad = 3
  elseif con >= level["Mala"] && con <  level["Muy Mala"]
    calidad = 4
  else #= extremadamente mala =#
    calidad = 5
  end
  return calidad;
end

#=
 
	ConcentraciónPromedioHoraria

	Def: Es el promedio o media aritmética de las concentraciones 
	registradas en el intervalo de tiempo de 60 minutos delimitado 
	por los minutos 0 y 59 de la hora. Para efectos del manejo de 
	datos se considerará válido, cuando se calcule con al menos el 
	75 % de las concentraciones registradas en la hora.
=#
function concentracionPromedioHoraria(concentracion)
  return concentracion[length(concentracion)]
end


# Indicator function  I(X)#

function I(X)
  if X > 0
    return 1.
  else
    return 0.
  end 
end

#= ----
  CPM()
---- =#  
function CPM(concentraciones, horas) 
  vals = concentraciones;
  lv = length(vals)
  if lv < horas;
    #=print("Not enough data\n\n")=#
    return -1 #= Not enough data available =# 
  end 
  tmp = Vector{Float64}
  tmp = Float64[]
  flag = Float64[]


  for j = lv:-1:lv-horas+1
      append!(tmp, vals[j])
      if vals[j] == 0
        append!(flag,0.)
      else
        append!(flag,1.)
      end
  end

  if flag[1]+flag[2]+flag[3] < 3;
    #println("Cannot compute moving average:[Missing data]")
    return 0 #= Not enough data available =# 
  end

  mi = minimum(tmp)
  ma = maximum(tmp)
  w = 1-(ma-mi)/ma;
  if w > 0.5
    W = w
  else
    W = .5
  end
  sum1 = 0.;
  sum2 = 0.;
  for j = 1:length(tmp)
      sum1 = sum1 + tmp[j]*W^(j-1)
      sum2 = sum2 + W^(j-1)*I(tmp[j])
  end
  wMA = sum1/sum2
  return wMA
end

function CPMAll(concentraciones, horas)
  tmp = Float64[]
  promedioMovil = Float64[]
  lv = length(concentraciones)
  if lv < horas;
    #=print("Not enough data\n\n")=#
    return [] #= Not enough data available =# 
  end

  for i = 1: horas+1
    append!(promedioMovil,0)
  end

  for i = horas+2:length(concentraciones)
    tmp = Float64[]
    tmp = concentraciones[i-horas+1:i]
    val = CPM(tmp, horas);   
    append!(promedioMovil,val)
  end

  return promedioMovil;
end

# ---- AnalyzeData ---- #

function AnalyzeData(data)

  concentrationPM10 = Vector{Float64}
  concentrationPM25 = Vector{Float64}
  concentrationCO = Vector{Float64}
  concentrationNO2 = Vector{Float64}
  concentrationsO3 = Vector{Float64}
  concentrationsSO2 = Vector{Float64}
  promMovil12PM10T = Vector{Float64}
  promMovil12PM25T = Vector{Float64}
  promMovil8COT = Vector{Float64}
  promMovil24SO2T = Vector{Float64}
  promHorariaNO2T = Vector{Float64}
  promMovil8O3T   = Vector{Float64}
  promHorariaO3T  = Vector{Float64}
  histCAPM10 = Vector{Float64}
  histCAPM25 = Vector{Float64}
  histCAO3 = Vector{Float64}
  histCANO2 = Vector{Float64}
  histCACO = Vector{Float64}
  histCASO2 = Vector{Float64}


  hourPM10 = Vector{Int32}
  hourPM25 = Vector{Int32}
  hourCO = Vector{Int32}
  hourNO2 = Vector{Int32}
  hourO3 = Vector{Int32}
  hourSO2 = Vector{Int32}
  calidadDelAirePM10 = "";
  calidadDelAirePM25 = "";
  calidadDelAireO3 = "";
  calidadDelAireCO = "";
  calidadDelAireNO = "";
  calidadDelAireSO2 = "";
  nivelDeRiesgoAsociadoPM10 = "";
  nivelDeRiesgoAsociadoPM25 = "";
  nivelDeRiesgoAsociadoO3 = "";
  nivelDeRiesgoAsociadoCO = "";
  nivelDeRiesgoAsociadoNO = "";
  nivelDeRiesgoAsociadoSO2 = "";
  promMovil12PM10 = -1
  promMovil12PM25 = -1
  promMovil8CO = -1
  promMovil24SO2 = -1
  promHorariaNO2 = -1
  promMovil8O3   = -1
  promHorariaO3   = -1

  stations = []

  for k in keys(data)
    state = data[k];
    for red in state["REDES"]
      for estacion in red["ESTACIONES"] 
       logEvent("ANALYZING DATA",state["NOMBRE"]*"-"*estacion["NOMBRE"])

        contaminantes = estacion["CONTAMINANTES"]
        concentrationPM10 = Float64[]
        concentrationPM25 = Float64[]
        concentrationCO = Float64[]
        concentrationNO2 = Float64[]
        concentrationO3 = Float64[]
        concentrationSO2 = Float64[]
        hourPM10 = Int32[]
        hourPM25 = Int32[]
        hourCO = Int32[]
        hourNO2 = Int32[]
        hourO3 = Int32[]
        hourSO2 = Int32[]
        calidadDelAirePM10 = "";
        calidadDelAirePM25 = "";
        calidadDelAireO3 = "";
        calidadDelAireCO = "";
        calidadDelAireNO = "";
        calidadDelAireSO2 = "";
        nivelDeRiesgoAsociadoPM10 = "";
        nivelDeRiesgoAsociadoPM25 = "";
        nivelDeRiesgoAsociadoO3 = "";
        nivelDeRiesgoAsociadoCO = "";
        nivelDeRiesgoAsociadoNO = "";
        nivelDeRiesgoAsociadoSO2 = "";
        cPM10 = 0
        cPM25 = 0
        cO3 = 0
        cSO2 = 0
        cNO2 = 0
        cCO = 0
        promMovil12PM10 = -1
        promMovil12PM25 = -1
        promMovil8CO = -1
        promMovil24SO2 = -1
        promHorariaNO2 = -1
        promMovil8O3   = -1
        promHorariaO3   = -1
        promMovil12PM10T = Float64[]
        promMovil12PM25T = Float64[]
        promMovil8COT = Float64[]
        promMovil24SO2T = Float64[]
        promHorariaNO2T = Float64[]
        promMovil8O3T   = Float64[]
        promHorariaO3T   = Float64[]
        histCAPM10 = Float64[]
        histCAPM25 = Float64[]
        histCAO3M = Float64[]
        histCAO3H = Float64[]
        histCAO3L = Float64[]
        histCANO2 = Float64[]
        histCACO = Float64[]
        histCASO2 = Float64[]
        
        if length( keys( contaminantes["PM10"] )) > 0       
          for valinfo in contaminantes["PM10"]
            append!(concentrationPM10,parse(Float64, valinfo["valor"]))
            append!(hourPM10,parse(Int32, valinfo["hora"]))
          end
          
          FilterConcentrations(concentrationPM10)
          checkMissingValues(concentrationPM10, hourPM10, 23)
          promMovil12PM10 = CPM(concentrationPM10, 12)
          promMovil12PM10T = CPMAll(concentrationPM10, 12)
          if length(promMovil12PM10T) > 0
             histCAPM10 = histCA(promMovil12PM10T, PM10L)
             writeTS("prom/"*red["CODIGO"]*"promMovil12PM10T.txt", hourPM10, promMovil12PM10T)
          end  
          if length(concentrationPM10) > 0
             writeTS("prom/"*red["CODIGO"]*"concentrationPM10.txt", hourPM10, concentrationPM10)
          end         
          c = CA(promMovil12PM10, PM10L)
          if promMovil12PM10 > 0
            calidadDelAirePM10 = airQuality[c]
            nivelDeRiesgoAsociadoPM10 = riskLevel[c]
            cPM10 = c;
          else
            calidadDelAirePM10 = "No disponible"
            nivelDeRiesgoAsociadoPM10 = "No disponible"
            cPM10 = 0;
          end
        else 
            calidadDelAirePM10 = "No disponible"
            nivelDeRiesgoAsociadoPM10 = "No disponible"
            cPM10 = 0;          
        end
        if length( keys( contaminantes["PM2.5"] )) > 0
          for valinfo in contaminantes["PM2.5"]
            append!(concentrationPM25,parse(Float64, valinfo["valor"]))
            append!(hourPM25,parse(Int32,valinfo["hora"]))
          end
          FilterConcentrations(concentrationPM25)
          checkMissingValues(concentrationPM25, hourPM25, 23)
          promMovil12PM25 = CPM(concentrationPM25,12)
          promMovil12PM25T = CPMAll(concentrationPM25, 12)
          if length(promMovil12PM25T) > 0
             histCAPM25 = histCA(promMovil12PM25T, PM25L)
             writeTS("prom/"*red["CODIGO"]*"promMovil12PM25T.txt", hourPM25, promMovil12PM25T)
          end
          if length(concentrationPM25) > 0
             writeTS("prom/"*red["CODIGO"]*"concentrationPM25.txt", hourPM25, concentrationPM25)
          end         

          c = CA(promMovil12PM25, PM25L)
          if promMovil12PM25 > 0
            calidadDelAirePM25 = airQuality[c]
            nivelDeRiesgoAsociadoPM25 = riskLevel[c] 
            cPM25 = c;
          else
            calidadDelAirePM25 = "No disponible"
            nivelDeRiesgoAsociadoPM25 = "No disponible"
            cPM25 = 0;          
          end 
        else
            calidadDelAirePM25 = "No disponible"
            nivelDeRiesgoAsociadoPM25 = "No disponible"
            cPM25 = 0;                  
        end
        if length( keys( contaminantes["CO"] )) > 0
          for valinfo in contaminantes["CO"]
            append!(concentrationCO,parse(Float64, valinfo["valor"]))
            append!(hourCO,parse(Int32, valinfo["hora"]))
          end
          #println(length(hourCO), length(concentrationCO))
          FilterConcentrations(concentrationCO)
          checkMissingValues(concentrationCO, hourCO, 23)
          promMovil8CO = CPM(concentrationCO,8)
          promMovil8COT = CPMAll(concentrationCO, 8)
          if length(promMovil8COT) > 0
             histCACO = histCA(promMovil8COT, COL)
             writeTS("prom/"*red["CODIGO"]*"promMovil8COT.txt", hourCO, promMovil8COT)
          end
          if length(concentrationCO) > 0
             writeTS("prom/"*red["CODIGO"]*"concentrationCO.txt", hourCO, concentrationCO)
          end         

          c = CA(promMovil8CO, COL)          
          if promMovil8CO > 0
            calidadDelAireCO = airQuality[c]
            nivelDeRiesgoAsociadoCO = riskLevel[c] 
            cCO = c  
          else
            calidadDelAireCO = "No disponible"
            nivelDeRiesgoAsociadoCO = "No disponible"
            cCO = 0          
          end 
        else
          calidadDelAireCO = "No disponible"
          nivelDeRiesgoAsociadoCO = "No disponible"
          cCO = 0;          
        end
        if length( keys( contaminantes["NO2"] )) > 0
          for valinfo in contaminantes["NO2"]
            append!(concentrationNO2,parse(Float64, valinfo["valor"]))
            append!(hourNO2,parse(Int32,valinfo["hora"]))
          end
          #println(length(hourNO2), length(concentrationNO2))
          FilterConcentrations(concentrationNO2)
          checkMissingValues(concentrationNO2, hourNO2, 23)
          promHorariaNO2 = concentracionPromedioHoraria(concentrationNO2)
          if length(concentrationNO2) > 0
             histCANO2 = histCA(concentrationNO2, NO2L)
             writeTS("prom/"*red["CODIGO"]*"promHorariaNO2.txt", hourNO2, concentrationNO2)
          end
          c = CA(promHorariaNO2, NO2L)          
          if promHorariaNO2 > 0
            calidadDelAireNO = airQuality[c]
            nivelDeRiesgoAsociadoNO = riskLevel[c]
            cNO2 = c;
          else
            calidadDelAireNO = "No disponible"
            nivelDeRiesgoAsociadoNO = "No disponible"
            cNO2 = 0;
          end 
        else
          calidadDelAireNO = "No disponible"
          nivelDeRiesgoAsociadoNO = "No disponible"
          cNO2 = 0;            
        end
        if length( keys( contaminantes["O3"] )) > 0
          for valinfo in contaminantes["O3"]
            append!(concentrationO3,parse(Float64, valinfo["valor"]))
            append!(hourO3,parse(Int32, valinfo["hora"]))
          end

          FilterConcentrations(concentrationO3)
          checkMissingValues(concentrationO3, hourO3, 23)
          promMovil8O3 = CPM(concentrationO3,8)          
          promHorariaO3 = concentracionPromedioHoraria(concentrationO3)
          promMovil8O3T = CPMAll(concentrationO3, 8)
          if length(promMovil8O3T) > 0
             histCAO3M = histCA(promMovil8O3T, O3LM)
             writeTS("prom/"*red["CODIGO"]*"promMovil8O3T.txt", hourO3, promMovil8O3T)
          end
          if length(concentrationO3) > 0
             histCAO3H = histCA(concentrationO3, O3LH)          
             writeTS("prom/"*red["CODIGO"]*"concentrationO3.txt", hourO3, concentrationO3)
          end         

          c1 = CA(promMovil8O3, O3LM)
          c2 = CA(promHorariaO3, O3LH)
          c = maximum([c1 c2]) 
          if c1==0 || c2 == 0
             c= 0
          end            
          if promMovil8O3 > 0 && promHorariaO3 > 0
            calidadDelAireO3 = airQuality[c]
            nivelDeRiesgoAsociadoO3 = riskLevel[c] 
            cO3 = c
          else
            calidadDelAireO3 = "No disponible"
            nivelDeRiesgoAsociadoO3 = "No disponible"
            cO3 = 0
          end 
        else
          calidadDelAireO3 = "No disponible"
          nivelDeRiesgoAsociadoO3 = "No disponible"
          cO3 = 0                    
        end
        if length( keys( contaminantes["SO2"] )) > 0
          for valinfo in contaminantes["SO2"]
            append!(concentrationSO2,parse(Float64, valinfo["valor"]))
            append!(hourSO2,parse(Int32, valinfo["hora"]))
          end
          FilterConcentrations(concentrationSO2)
          checkMissingValues(concentrationSO2, hourSO2, 23)
          promMovil24SO2 = CPM(concentrationSO2,24) 
          promMovil24SO2T = CPMAll(concentrationSO2, 8)
          if length(promMovil24SO2T) > 0
             histCASO2 = histCA(promMovil24SO2T, SO2L)
             print("J")
             writeTS("prom/"*red["CODIGO"]*"promMovil24SO2T.txt", hourSO2, promMovil24SO2T)
          end
          if length(concentrationSO2) > 0
             print("K")
             writeTS("prom/"*red["CODIGO"]*"concentrationSO2.txt", hourSO2, concentrationSO2)
          end          
          index = CA(promMovil24SO2, SO2L)                
          if promMovil24SO2 > 0
            calidadDelAireSO2 = airQuality[index]
            nivelDeRiesgoAsociadoSO2 = riskLevel[index] 
            cSO2 = index
          else
            calidadDelAireSO2 = "No dsiponible"
            nivelDeRiesgoAsociadoSO2 = "No disponible" 
            cSO2 = 0
          end 
        else
          calidadDelAireSO2 = "No dsiponible"
          nivelDeRiesgoAsociadoSO2 = "No disponible" 
          cSO2 = 0        
        end
        ca = maximum([cPM10,cPM25,cSO2,cCO,cNO2,cO3])
        if ca == 0
          ca = 6 # "No disponible"
        end
        station = Dict( "STATE" => state["NOMBRE"],
                        "NAME" => red["NOMBRE"],
                        "CODE" => red["CODIGO"],
                        "LAT" => estacion["GPS"]["LAT"],
                        "LNG" => estacion["GPS"]["LNG"],
                        "IDSTATION" => estacion["ID"],
                        "NAMESTATION" => estacion["NOMBRE"],
                        "PM10ch" => concentrationPM10,
                        "PM2.5ch" => concentrationPM25,
                        "COch" =>  concentrationCO,
                        "NO2ch" => concentrationNO2,
                        "O3ch" =>  concentrationO3,
                        "SO2ch" => concentrationSO2,
                        "PM10h" => hourPM10,
                        "PM2.5h" => hourPM25,
                        "COh" =>  hourCO,
                        "NO2h" => hourNO2,
                        "O3h" =>  hourO3,
                        "SO2h" => hourSO2,
                        "promMovil12PM10" => Int32(round(promMovil12PM10)), #cambiar rutinas redondeo
                        "promMovil12PM2.5" => Int32(round(promMovil12PM25)),
                        "promMovil8CO" => round(promMovil8CO, digits=2),
                        "promMovil8O3" => round(promMovil8O3,digits=2),
                        "promHorariaO3" => round(promHorariaO3,digits=3),
                        "promMovil24SO2"=> round(promMovil24SO2,digits=3),
                        "promHorariaNO2" => round(promHorariaNO2,digits=3),
                        "calidadDelAirePM10" => calidadDelAirePM10,
                        "calidadDelAirePM2.5" => calidadDelAirePM25,
                        "calidadDelAireCO" => calidadDelAireCO,
                        "calidadDelAireNO2" => calidadDelAireNO,
                        "calidadDelAireO3" => calidadDelAireO3,
                        "calidadDelAireSO2" => calidadDelAireSO2,
                        "nivelDeRiesgoAsociadoPM10" => nivelDeRiesgoAsociadoPM10,
                        "nivelDeRiesgoAsociadoPM2.5" => nivelDeRiesgoAsociadoPM25,
                        "nivelDeRiesgoAsociadoCO" => nivelDeRiesgoAsociadoCO,
                        "nivelDeRiesgoAsociadoNO2" => nivelDeRiesgoAsociadoNO,
                        "nivelDeRiesgoAsociadoO3" => nivelDeRiesgoAsociadoO3,
                        "nivelDeRiesgoAsociadoSO2" => nivelDeRiesgoAsociadoSO2,
                        "calidadDelAire" => ca,  
                        "startDate" => startDate,
                        "now" => Dates.now(), #CT
                        "airQualityTags" => airQuality,
                        "TODAY" => Dates.today(),
                        "promMovil12PM10T" => promMovil12PM10T,
                        "promMovil12PM2.5T" => promMovil12PM25T,
                        "promMovil8COT" => promMovil8COT,
                        "promMovil8O3T" => promMovil8O3T,
                        "promMovil24SO2T"=> promMovil24SO2T,
                        "histCAPM10" => histCAPM10,
                        "histCAPM25" => histCAPM25,
                        "histCAO3M" => histCAO3M,
                        "histCAO3L" => histCAO3L,
                        "histCANO2" => histCANO2,
                        "histCASO2" => histCASO2,
                        "histCACO" => histCACO
                        )            
        push!(stations, station)              
      end  
    end
  end

  writeAnalysisFile(stations)

end

function dumpSummary()
  io = open("analysis.json", "r");
  text = read(io, String);
  stations = JSON.parse(text);
  close(io);

  file = open("dump/dump.txt", "w")
  for station in stations

    println(file,"***************************************************************")
    println(file,"Estado:", station["STATE"])
    println(file,"Estación:", station["NAME"])
    println(file,"Código de la estación:", station["CODE"])
    println(file,"Estación:", station["NAME"])
    println(file,"ID de la estación:", station["IDSTATION"])
    println(file,"Nombre de la estación:", station["NAMESTATION"])
    println(file,"Latitud:", station["LAT"])
    println(file,"Longitud:", station["LNG"])
    #if station["calidadDelAire"] > 0#
      println(file,"Calidad del Aire:", airQuality[station["calidadDelAire"]])
    #else#
    #  println(file,"Calidad del Aire:", "No disponible")#
    #end#
    println(file,"---------------------------------------------------------------")
    if  station["promMovil12PM10"] > 0
      println(file,"PM10  (promedio móvil 12h):", station["promMovil12PM10"], "(ug/m3)")
    else
      println(file,"PM10  (promedio móvil 12h):", "No disponible")
    end  
    println(file,"PM10  (calidad del aire):", station["calidadDelAirePM10"] )
    println(file,"PM10  (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoPM10"] )
    println(file,"---------------------------------------------------------------")
    if station["promMovil12PM2.5"] > 0
        println(file,"PM2.5 (promedio móvil 12h):", station["promMovil12PM2.5"], "(ug/m3)")
    else
      println(file,"PM2.5  (promedio móvil 12h):", "No disponible")
    end           
    println(file,"PM2.5 (calidad del aire):", station["calidadDelAirePM2.5"] )
    println(file,"PM2.5 (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoPM2.5"] )
    println(file,"---------------------------------------------------------------")
    if station["promMovil8CO"] > 0
      println(file,"CO    (promedio móvil 8h):", station["promMovil8CO"], "(ppm)")
    else
      println(file,"CO  (promedio móvil 8h):", "No disponible")
    end
    println(file,"CO    (calidad del aire):", station["calidadDelAireCO"] )
    println(file,"CO    (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoCO"] )     
    println(file,"---------------------------------------------------------------") 
    if   station["promMovil24SO2"] > 0    
      println(file,"SO2   (promedio móvil 24h):", station["promMovil24SO2"], "(ppm)")
    else
      println(file,"SO  (promedio móvil 24h):", "No disponible")
    end
        
    println(file,"SO2   (calidad del aire):", station["calidadDelAireSO2"] )
    println(file,"SO2   (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoSO2"] )    
    println(file,"---------------------------------------------------------------")  
    if  station["promHorariaO3"] > 0 
      println(file,"O3    (promedio horaria):", station["promHorariaO3"], "(ppm)")
    else
      println(file,"O3  (promedio horaria):", "No disponible")
    end
    if  station["promMovil8O3"] > 0 
      println(file,"O3    (promedio móvil 8h):", station["promMovil8O3"], "(ppm)")
    else
      println(file,"O3    (promedio móvil 8h):", "No disponible")
    end
    println(file,"O3    (calidad del aire):", station["calidadDelAireO3"] )
    println(file,"O3    (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoO3"] )    
    println(file,"---------------------------------------------------------------") 
    if   station["promHorariaNO2"] > 0 
      println(file,"NO2   (promedio horaria):", station["promHorariaNO2"], "(ppm)")
    else
      println(file,"NO2  (promedio horaria):", "No disponible")
    end    
    println(file,"NO2   (calidad del aire):", station["calidadDelAireNO2"] )
    println(file,"NO2   (nivel de riesgo asociado):", station["nivelDeRiesgoAsociadoNO2"] )    
  end
  close(file)
end


#= - - - - - - - Main - - - - - - - - - =#

while(true)
  logEvent("STARTING", "Requesting SINAICA's data.")
  retrieveData()#
  data = readDataFile();
  logEvent("PROCESSING", "Conducting data analysis.")
  AnalyzeData(data)
  dumpSummary()
  logEvent("PROCESSING", "Finished data analysis.")
  logEvent("PROCESSING", "Waiting for new data.")  
	t = Timer(2400,interval=0) #= fourty-minute delay =#
	wait(t)
end










