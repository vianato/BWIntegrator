{$R-,C-,Q-,O+,H+}

unit bwIntegrator;

interface
{$WARN SYMBOL_PLATFORM OFF}
{$WARN SYMBOL_DEPRECATED OFF}

uses
  System.Classes,
  System.Generics.Collections;

procedure IntegratorEnterProc(const procId: Integer);
procedure IntegratorExitProc(const procId: Integer);
procedure CaptureAndHandleException(const procId: Integer; const exceptObject: TObject); overload;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.IniFiles,
  System.StrUtils,
  TlHelp32,
  Vcl.Forms,
  Winapi.Windows,
  bwAPIMetricClient,
  bwAPIEventClient,
  bwAPILogClient,
  bwAPIExceptionClient,
  bwProcessHandler,
  bwConfigFileHandler,
  uMetrics.statsDClient.interf,
  uMetrics.statsDClient.impl, uMetrics.statsDClientSender.impl,
  uMetrics.serviceCheck, uMetrics.statsDClientSender.interf, uMetrics.header,
  uMetrics.event;

var
  process: TProcess;
  config: TConfigFile;
  apiMetricClient: TAPIMetricClient;
  apiEventClient: TAPIEventClient;
  apiLogClient: TAPILogClient;
  apiExceptionClient: TAPIExceptionClient;
  senderStatsDClient: IDataDogStatsClientSender;
  datadogService: TDataDogServiceCheck;
  statsDClient: IDataDogStatsClient;

procedure IntegratorEnterProc(const procId: Integer);
var
  index: Integer;
begin
    index := process.Id.IndexOf(procId);
  process.StartTime[index] := 0;
  process.StopTime[index] := 0;
  process.Timestamp[index] := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
  if procId > 0 then
    // Inicio do calculo do tempo de execucao
    process.StartTime[index] := MillisecondOfTheDay(Now);
end;

procedure IntegratorExitProc(const procId: Integer);
var
  index: Integer;
  event: TDataDogEvent;
  exceptionClass: String;
  exceptionMsg: String;
  // TODO: ******************
  token: TStringList;
  strMetric: String;
  strUnit: String;
  strClass: String;
  strMethod: String;
  i: Integer;
begin
  if procId > 0 then
  begin
    index := process.Id.IndexOf(procId);
    // Termino do calculo do tempo de execucao
    process.StopTime[index] := MillisecondOfTheDay(Now);

    // Envio das metricas via API
    if (config.MIntegrationType = 'api') or (config.MIntegrationType = 'both') then
    begin
      try
        TThread.CreateAnonymousThread(
          procedure
          begin
            apiMetricClient.Execute(config, process.Name[index], 'count', 1, process.Timestamp[index]);
          end).Start;

        TThread.CreateAnonymousThread(
          procedure
          begin
            apiMetricClient.Execute(config, process.Name[index], 'time', process.StopTime[index] - process.StartTime[index], process.Timestamp[index]);
          end).Start;
      except
        on e: Exception do
          apiExceptionClient.Execute(config, process.Name[index], e);
      end;
    end;

    // Envio das metricas via statsD
    // TODO: ****************Inserir métodos Execute e levar pra uma camada mais alta
    if (config.MIntegrationType = 'statsd') or (config.MIntegrationType = 'both') then
    begin
      token := TStringList.Create;
      try
        token.Clear;
        ExtractStrings(['.'], [], PChar(process.Name[index]), token);
        for i := 0 to token.Count - 1 do
        begin
          case i of
            0: strUnit := token[i];
            1: strClass := token[i];
            2: strMethod := token[i];
          else
            break;
          end;
        end;
      finally
        token.Free;
      end;
      // Subir somente 'BWIntegrator' como metrica (acrescido de count/time)
      strMetric := 'BWIntegrator';

      try
        // Subir somente 'BWIntegrator' como metrica (acrescido de count/time)
        statsDClient.Count(strMetric + '.count', 1, process.Timestamp[index], TDataDogTags.Create(process.Thread, 'source:delphi11', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, 'unit:' + strUnit, 'class:' + strClass, 'method:' + strMethod, 'type:count', config.MTags));
        statsDClient.Count(strMetric + '.time', process.StopTime[index] - process.StartTime[index], process.Timestamp[index], TDataDogTags.Create(process.Thread, 'source:delphi11', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, 'unit:' + strUnit, 'class:' + strClass, 'method:' + strMethod, 'type:time', config.MTags));
//        statsDClient.RecordExecutionTime(strMetric + '.time', process.StopTime[index] - process.StartTime[index], process.Timestamp[index], TDataDogTags.Create(process.Thread, 'source:delphi11', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, 'unit:' + strUnit, 'class:' + strClass, 'method:' + strMethod, 'type:time', config.MTags));
      except
        on e: Exception do
        begin
          event := TDataDogEvent.Create;
          exceptionClass := Exception(ExceptObject).ClassName;
          exceptionMsg := Exception(ExceptObject).Message;
          event.Title := 'BWIntegrator.' + config.AppName + '.' + process.Name[index] + ': ' + exceptionClass;
          event.Text := exceptionMsg;
          event.Priority := ddLow;
          event.AlertType := ddError;
          statsDClient.RecordEvent(event, TDataDogTags.Create(process.Thread, 'source:delphi', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, config.ETags));
          event.Free;
          // Subir somente 'BWIntegrator' como metrica (acrescido de count/time)
          statsDClient.Count(strMetric + '.count', 1, process.Timestamp[index], TDataDogTags.Create(process.Thread, 'source:delphi', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, 'unit:' + strUnit, 'class:' + strClass, 'method:' + strMethod, 'type:count', 'exceptionClass:' + exceptionClass, config.MTags));
        end;
      end;
    end;
  end;
end;

procedure CaptureAndHandleException(const procId: Integer; const exceptObject: TObject);
var
  index: Integer;
  event: TDataDogEvent;
  exceptionClass: String;
  exceptionMsg: String;
  // TODO: ******************
  token: TStringList;
  strMetric: String;
  strUnit: String;
  strClass: String;
  strMethod: String;
  i: Integer;
begin
  if procId > 0 then
  begin
    index := process.Id.IndexOf(procId);

    // Envio das metricas via API
    if (config.MIntegrationType = 'api') or (config.MIntegrationType = 'both') then
    begin
      apiExceptionClient.Execute(config, process.Name[index], exceptObject);
    end;
    // Envio das metricas via statsD
    if (config.MIntegrationType = 'statsd') or (config.MIntegrationType = 'both') then
    begin
      // TODO: ******************
      // Criar a TExceptionClient e suas herdeiras TStatsDExceptionClient / TAPIExceptionClient
      event := TDataDogEvent.Create;
      exceptionClass := Exception(ExceptObject).ClassName;
      exceptionMsg := Exception(ExceptObject).Message;
      event.Title := 'BWIntegrator.' + config.AppName + '.' + process.Name[index] + ': ' + exceptionClass;
      event.Text := exceptionMsg;
      event.Priority := ddLow;
      event.AlertType := ddError;
      statsDClient.RecordEvent(event, TDataDogTags.Create(process.Thread, 'source:delphi', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, config.ETags));
      event.Free;

      token := TStringList.Create;
      try
        token.Clear;
        ExtractStrings(['.'], [], PChar(process.Name[index]), token);
        for i := 0 to token.Count - 1 do
        begin
          case i of
            0: strUnit := token[i];
            1: strClass := token[i];
            2: strMethod := token[i];
          else
            break;
          end;
        end;
      finally
        token.Free;
      end;
      strMetric := 'BWIntegrator.count';
      statsDClient.Count(strMetric, 1, process.Timestamp[procId], TDataDogTags.Create(process.Thread, 'source:delphi', 'clientid:' + config.ClientId, 'hostname:' + config.Hostname, 'os:' + config.OS, 'service:' + config.AppName, 'unit:' + strUnit, 'class:' + strClass, 'method:' + strMethod, 'type:count', 'exceptionClass:' + exceptionClass, config.MTags));
    end;
  end;
end;

procedure Initialize;
begin
  process := TProcess.Create;
  config := TConfigFile.Create;
  apiMetricClient := TAPIMetricClient.Create;
  apiEventClient := TAPIEventClient.Create;
  apiLogClient := TAPILogClient.Create;
  apiExceptionClient := TAPIExceptionClient.Create;
  datadogService := TDataDogServiceCheck.Create;
  senderStatsDClient := TDataDogStatsClientSender.Create(datadogService);
  statsDClient := TDataDogStatsClientImpl.Create(senderStatsDClient);
end;

procedure Finalize;
begin
  process.Free;
  config.Free;
//  apiMetricClient.Free;
//  apiEventClient.Free;
//  apiLogClient.Free;
//  apiExceptionClient.Free;
  datadogService.Free;
end;

procedure LoadProcess;
var
  buffer: array [0..255] of Char;
  fTxt: TextFile;
  fileName: String;
  text: String;
begin
  GetModuleFileName(HInstance, buffer, 256);
  process.Module := String(buffer);
  fileName := Copy(process.Module, 1, Length(process.Module) - Length(ExtractFileExt(process.Module))) + '.gpt';
  try
    if not FileExists(fileName) then
      // TODO: Colocar uma caixa de dialogo informando
      raise EFileNotFoundException.Create('Arquivo de instrumentacao "' + fileName + '" nao encontrado.')
    else begin
      try
        assignfile(fTxt, fileName);
        reset(fTxt);
        while not Eof(fTxt) do
        begin
          readln(fTxt, text);
          process.Id.Add(StrToInt(text));
          readln(fTxt, text);
          process.Name.Add(text);
          process.StartTime.Add(0);
          process.StopTime.Add(0);
          process.Timestamp.Add(0);
        end;
      finally
        closefile(fTxt);
      end;
    end;
  except
    on e: Exception do
    begin
      // Capturar e tratar eventuais excecoes
      apiExceptionClient.Execute(config, 'BWIntegrator.bwIntegrator.LoadProc', e);
      // Abortar a execucao, nao pode ser continuada sem os dados
      Application.Terminate;
    end;
  end;
end;

initialization
  try
    try
      // Criar as estruturas utilizadas
      Initialize;
      // Carregar os objetos indexados pela instrumentacao previa
      LoadProcess;
      // Habilitar a coleta e envio de logs para o Datadog
      if config.UseLogFile then
      begin
        try
          TThread.CreateAnonymousThread(
            procedure
            begin
              apiLogClient.ReadLogFile(config);
            end).Start;
        except
          on e: Exception do
            // Capturar e tratar eventuais excecoes
            apiExceptionClient.Execute(config, 'BWIntegrator.bwIntegrator.initialization', e);
        end;
      end;
    except
      on e: Exception do
      begin
        // Capturar e tratar eventuais excecoes
        apiExceptionClient.Execute(config, 'BWIntegrator.bwIntegrator.initialization', e);
      end;
    end;
  except
    on e: Exception do
    begin
      // Capturar e tratar eventuais excecoes
      apiExceptionClient.Execute(config, 'BWIntegrator.bwIntegrator.initialization', e);
    end;
  end;

finalization
  // Liberar as estruturas utilizadas
  Finalize;

end.

