unit bwMetricHandler;

interface

uses
  System.Classes;

procedure LoadMetricConfig;
procedure ProcessTimeMetric(const metricName: String; const metricValue, timestamp: Int64);
procedure ProcessCountMetric(const metricName: String; const metricValue, timestamp: Int64);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.IniFiles,
  System.StrUtils,
  System.DateUtils,
  Vcl.Dialogs,
  System.JSON,
  System.Threading,
  System.Net.HttpClient,
  System.Net.URLClient,
  TlHelp32,
  Winapi.Windows,
  bwExceptionHandler,
  Messages, Variants, Graphics, Controls, Forms, StdCtrls;
var
  apiKey  : String;
  clientId: String;
  endpoint: String;
  tags    : String;
  os      : String;
  hostname: String;
  appName : String;

function GetHostName: String;
var
  buffer: array [0..MAX_COMPUTERNAME_LENGTH + 1] of Char;
  size: DWORD;
begin
  size := Length(buffer);
  if GetComputerName(buffer, size) then
    result := buffer
  else
    result := '';
end;

function GetOS: String;
var
  buffer: String;
begin
  buffer := TOSVersion.ToString;
  if buffer <> '' then
    result := buffer
  else
    result := '';
end;

function GetApplicationName: String;
begin
  result := ExtractFileName(ParamStr(0));
  result := ChangeFileExt(result, '');
end;

procedure SendMetricToSAS(const metric: String);
var
  HttpClient: THTTPClient;
  RequestContent: TStringStream;
//  ResponseContent: String;
begin
  HttpClient := THTTPClient.Create;
  try
    HttpClient.Accept := 'application/json';
    HttpClient.ContentType := 'application/json';
    HttpClient.CustomHeaders['DD-API-KEY'] := apiKey;

    RequestContent := TStringStream.Create(metric, TEncoding.UTF8);
    try
//      ResponseContent := HttpClient.Post(endpoint, RequestContent).ContentAsString();
      HttpClient.Post(endpoint, RequestContent);
    finally
      RequestContent.Free;
    end;
  finally
    HttpClient.Free;
  end;
end;

procedure ProcessTimeMetric(const metricName: String; const metricValue, timestamp: Int64);
var
  content : String;
  strMetric: String;

  Str: string;
  Parte: string;
  Posicao: Integer;
  Count: Integer;
  i: Integer;
begin
  os := GetOS;
  hostname := GetHostName;
  appName := GetApplicationName;

  Count := 0;
  for i := 1 to Length(metricName) do
  begin
    if Copy(metricName, i, Length('.')) = '.' then
    begin
      Inc(Count);

      if Count = 2 then
      begin
        Posicao := i;
        Break;
      end;
    end;
  end;

  strMetric := Copy(metricName, 0, Posicao - 1);
  Parte := Copy(metricName, Posicao + 1, Length(metricName) - Posicao + 1);

  content := '{' +
    '"series": [' +
      '{' +
        '"metric": "' + 'BWintegrator.' + appName + '.' + strMetric + '", ' +
        '"points": [' +
          '{' +
            '"timestamp": ' + IntToStr(timestamp) + ', ' +
            '"value": ' + IntToStr(metricValue) +
          '}' +
        '], ' +
        '"tags": [' +
          '"source:delphi", ' +
          '"clientid:' + clientId + '", ' +
          '"hostname:' + hostName + '", ' +
          '"os:' + os + '", ' +
          '"service:' + appName + '", ' +
          '"metodo:' + parte + '"' +
          '' + tags + // acrescenta mais tags pelo arquivo .ini
        '], ' +
        '"type": 1, ' +
        '"unit": "millisecond", ' +
        '"interval": 10' +
      '}' +
    ']' +
  '}';

  SendMetricToSAS(content);
end;

procedure ProcessCountMetric(const metricName: String; const metricValue, timestamp: Int64);
var
  content : String;
  strMetric: String;

  Str: string;
  Parte: string;
  Posicao: Integer;
  Count: Integer;
  i: Integer;
begin
  os := GetOS;
  hostname := GetHostName;
  appName := GetApplicationName;

  Count := 0;
  for i := 1 to Length(metricName) do
  begin
    if Copy(metricName, i, Length('.')) = '.' then
    begin
      Inc(Count);

      if Count = 2 then
      begin
        Posicao := i;
        Break;
      end;
    end;
  end;

  strMetric := Copy(metricName, 0, Posicao - 1);
  Parte := Copy(metricName, Posicao + 1, Length(metricName) - Posicao + 1);

  content := '{' +
    '"series": [' +
      '{' +
        '"metric": "' + 'BWintegrator.' + appName + '.' + metricName + '", ' +
        '"points": [' +
          '{' +
            '"timestamp": ' + IntToStr(timestamp) + ', ' +
            '"value": ' + IntToStr(metricValue) +
          '}' +
        '], ' +
        '"tags": [' +
          '"source:delphi", ' +
          '"clientid:' + clientId + '", ' +
          '"hostname:' + hostName + '", ' +
          '"os:' + os + '", ' +
          '"service:' + appName + '", ' +
          '"metodo:' + parte + '"' +
          '' + tags + // acrescenta mais tags pelo arquivo .ini
        '], ' +
        '"type": 1, ' +
        '"unit": "count", ' +
        '"interval": 10' +
      '}' +
    ']' +
  '}';

  SendMetricToSAS(content);
end;

procedure LoadMetricConfig;
var
  buffer: array [0..256] of char;
  auxTag: String;
  module: String;
  ini   : String;
begin
  GetModuleFileName(HInstance, buffer, 256);
  module := string(buffer);
  ini := ExtractFilePath(module) + 'bwTools.ini';
  try
    if not FileExists(ini) then
      raise EFileNotFoundException.Create('Arquivo de inicialização "' + ini + '" não encontrado.')
    else begin
      with TIniFile.Create(ini) do
      begin
        try
          apiKey   := ReadString('General', 'ApiKey', '');
          clientId := ReadString('General', 'ClientId', '');
          endpoint := ReadString('Metrics', 'Endpoint', 'https://api.datadoghq.com/api/v2/series');
          for var i := 1 to 5 do
          begin
            auxTag := ReadString('Metrics', 'Tag' + IntToStr(i), '');
            if auxTag <> '' then
              tags := tags + ', "' + auxTag + '"'
          end;
        finally
          Free;
        end;
      end;
    end;
  except
    on e: Exception do
    begin
      // Capturar e tratar eventuais excecoes
      CaptureAndHandleException('bwMetricHandler.LoadMetricConfig', e);
    end;
  end;
end;

initialization

finalization

end.

