#pragma author npatch
#pragma description Garmin .fit Binary
#pragma version 0.8

import std.core;
import std.string;
import std.mem;
import std.time;
import std.math;

#pragma loop_limit 400000

//#define DEBUG_MODE

/*
Tested against normal fit files. For compressed headers and other edge cases:
check github.com/NPatch/fit-format-imhex-pattern
*/

using Architecture;

enum Architecture : u8
{
    LittleEndian = 0x0,
    BigEndian = 0x1
};

Architecture global_architecture @ 0x0E [[hidden]];

fn ArchToEndian(Architecture a)
{
    if(a == Architecture::BigEndian)
    {
        return std::mem::Endian::Big;
    }
    return std::mem::Endian::Little;
};

//Has to be here because later on, it messes up things between calculations on local data, as well as, calculations on the file data/fit protocol data itself. Becomes a mess to do properly.
std::core::set_endian(ArchToEndian(global_architecture));

using EpochTime = u32;
using DateTime = u32;
using LocalDateTime = u32;
//custom epoch required by Garmin (Sunday, December 31, 1989 at 12:00:00 AM)
le u32 epoch_offset = 631065600;

u8 header_with_crc = 14;
u8 header_without_crc = 12;
//header crc  fields are optional but checking against header's own field
//throws "Cannot access data of type that hasn't been placed in memory." error.
//So, we prefetch it
u8 prefetched_header_size @ 0x00 [[hidden]]; 

using MsgNum;
using FitBaseTypeEnum;
fn fit_base_type_formatter(u8 fbt)
{
    u8 xiaomi_accounted_value = fbt;
    if((xiaomi_accounted_value >= 0x03 && xiaomi_accounted_value <= 0x06)
        || (xiaomi_accounted_value >= 0x08 && xiaomi_accounted_value <= 0x09)
        || (xiaomi_accounted_value >= 0x0B && xiaomi_accounted_value <= 0x0C)
        || (xiaomi_accounted_value >= 0x0E && xiaomi_accounted_value <= 0x10)
    )
    {
        xiaomi_accounted_value += 0x80;
    }
    FitBaseTypeEnum fbte = xiaomi_accounted_value;
    std::format("{}({})", std::string::to_string(fbte), fbt);
};

fn fit_base_type_formatter_2(auto fbt)
{
    match(fbt)
    {
        (0): {
            return "FitBaseTypeEnum::Enum";
        }
        (1): {
            return "FitBaseTypeEnum::Sint8";
        }
        (2): {
            return "FitBaseTypeEnum::Uint8";
        }
        (3|131): {
            return "FitBaseTypeEnum::Sint16";
        }
        (4|132): {
            return "FitBaseTypeEnum::Uint16";
        }
        (5|133): {
            return "FitBaseTypeEnum::Sint32";
        }
        (6|134): {
            return "FitBaseTypeEnum::Uint32";
        }
        (7): {
            return "FitBaseTypeEnum::String";
        }
        (8|136): {
            return "FitBaseTypeEnum::Float32";
        }
        (9|137): {
            return "FitBaseTypeEnum:Float64";
        }
        (10): {
            return "FitBaseTypeEnum::Uint8z";
        }
        (11|139): {
            return "FitBaseTypeEnum:Uint16z";
        }
        (12|140): {
            return "FitBaseTypeEnum::Uint32z";
        }
        (13): {
            return "FitBaseTypeEnum::Byte";
        }
        (14|142): {
            return "FitBaseTypeEnum::Sint64";
        }
        (15|143): {
            return "FitBaseTypeEnum::Uint64";
        }
        (16|144): {
            return "FitBaseTypeEnum::Uint64z";
        }
        (255): {
            return "FitBaseTypeEnum:Invalid";
        }
    }
    
};

using FieldDefinition;
using FixedHeader;

fn get_crc(u16 crc, u8 byte)
{
   const u16 crc_table[16] =
   {
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
   };
   u16 tmp;

   // compute checksum of lower four bits of byte
   tmp = crc_table[crc & 0xF];
   crc = (crc >> 4) & 0x0FFF;
   crc = crc ^ tmp ^ crc_table[byte & 0xF];

   // now compute checksum of upper four bits of byte
   tmp = crc_table[crc & 0xF];
   crc = (crc >> 4) & 0x0FFF;
   crc = crc ^ tmp ^ crc_table[(byte >> 4) & 0xF];

   return crc;
};

fn check_crc(u16 crc_init, ref auto array, u32 data_size)
{
    u16 crc = crc_init;
    for(u32 i=0,i<data_size, i += 1)
    {
        crc = get_crc(crc, array[i]);
    }
    return crc;
};

u32 time_created_addr = 0;
u32 fixed_header_addr = sizeof(DateTime);
u32 defs_array_addr = fixed_header_addr + sizeof(FixedHeader);

fn format_local_datetime(auto epoch) {
    std::time::EpochTime fixed = epoch + epoch_offset;
    std::core::set_endian(std::mem::Endian::Little);
    return std::format("{} ({})", std::time::format(std::time::to_local(fixed)), fixed);
};

fn format_datetime(auto epoch) {
    std::time::EpochTime fixed = epoch + epoch_offset;
    std::core::set_endian(std::mem::Endian::Little);
    return std::format("{} ({})", std::time::format(std::time::to_utc(fixed)), fixed);
};

std::mem::Section scratch = std::mem::create_section("Scratch");
DateTime scratch_time_created @ time_created_addr in scratch [[format("format_local_datetime")]];
FixedHeader scratch_fix_header @ fixed_header_addr in scratch;
FieldDefinition scratch_defs[256] @ defs_array_addr in scratch;

enum MsgNum : u16
{
    FileId                         = 0x0000,        // 0
    Capabilities                   = 0x0001,        // 1
    DeviceSettings                 = 0x0002,        // 2
    UserProfile                    = 0x0003,        // 3
    HrmProfile                     = 0x0004,        // 4
    SdmProfile                     = 0x0005,        // 5
    BikeProfile                    = 0x0006,        // 6
    ZonesTarget                    = 0x0007,        // 7
    HrZone                         = 0x0008,        // 8
    PowerZone                      = 0x0009,        // 9
    MetZone                        = 0x000A,        // 10
    Sport                          = 0x000C,        // 12
    TrainingSettings               = 0x000D,        // 13
    Goal                           = 0x000F,        // 15
    Session                        = 0x0012,        // 18
    Lap                            = 0x0013,        // 19
    Record                         = 0x0014,        // 20
    Event                          = 0x0015,        // 21
    DeviceInfo                     = 0x0017,        // 23
    Workout                        = 0x001A,        // 26
    WorkoutStep                    = 0x001B,        // 27
    Schedule                       = 0x001C,        // 28
    WeightScale                    = 0x001E,        // 30
    Course                         = 0x001F,        // 31
    CoursePoint                    = 0x0020,        // 32
    Totals                         = 0x0021,        // 33
    Activity                       = 0x0022,        // 34
    Software                       = 0x0023,        // 35
    FileCapabilities               = 0x0025,        // 37
    MesgCapabilities               = 0x0026,        // 38
    FieldCapabilities              = 0x0027,        // 39
    FileCreator                    = 0x0031,        // 49
    BloodPressure                  = 0x0033,        // 51
    SpeedZone                      = 0x0035,        // 53
    Monitoring                     = 0x0037,        // 55
    TrainingFile                   = 0x0048,        // 72
    Hrv                            = 0x004E,        // 78
    AntRx                          = 0x0050,        // 80
    AntTx                          = 0x0051,        // 81
    AntChannelId                   = 0x0052,        // 82
    Length                         = 0x0065,        // 101
    MonitoringInfo                 = 0x0067,        // 103
    Pad                            = 0x0069,        // 105
    SlaveDevice                    = 0x006A,        // 106
    Connectivity                   = 0x007F,        // 127
    WeatherConditions              = 0x0080,        // 128
    WeatherAlert                   = 0x0081,        // 129
    CadenceZone                    = 0x0083,        // 131
    Hr                             = 0x0084,        // 132
    SegmentLap                     = 0x008E,        // 142
    MemoGlob                       = 0x0091,        // 145
    SegmentId                      = 0x0094,        // 148
    SegmentLeaderboardEntry        = 0x0095,        // 149
    SegmentPoint                   = 0x0096,        // 150
    SegmentFile                    = 0x0097,        // 151
    WorkoutSession                 = 0x009E,        // 158
    WatchfaceSettings              = 0x009F,        // 159
    GpsMetadata                    = 0x00A0,        // 160
    CameraEvent                    = 0x00A1,        // 161
    TimestampCorrelation           = 0x00A2,        // 162
    GyroscopeData                  = 0x00A4,        // 164
    AccelerometerData              = 0x00A5,        // 165
    ThreeDSensorCalibration        = 0x00A7,        // 167
    VideoFrame                     = 0x00A9,        // 169
    ObdiiData                      = 0x00AE,        // 174
    NmeaSentence                   = 0x00B1,        // 177
    AviationAttitude               = 0x00B2,        // 178
    Video                          = 0x00B8,        // 184
    VideoTitle                     = 0x00B9,        // 185
    VideoDescription               = 0x00BA,        // 186
    VideoClip                      = 0x00BB,        // 187
    OhrSettings                    = 0x00BC,        // 188
    ExdScreenConfiguration         = 0x00C8,        // 200
    ExdDataFieldConfiguration      = 0x00C9,        // 201
    ExdDataConceptConfiguration    = 0x00CA,        // 202
    FieldDescription               = 0x00CE,        // 206
    DeveloperDataId                = 0x00CF,        // 207
    MagnetometerData               = 0x00D0,        // 208
    BarometerData                  = 0x00D1,        // 209
    OneDSensorCalibration          = 0x00D2,        // 210
    MonitoringHrData               = 0x00D3,        // 211
    TimeInZone                     = 0x00D8,        // 216
    Set                            = 0x00E1,        // 225
    StressLevel                    = 0x00E3,        // 227
    MaxMetData                     = 0x00E5,        // 229
    DiveSettings                   = 0x0102,        // 258
    DiveGas                        = 0x0103,        // 259
    DiveAlarm                      = 0x0106,        // 262
    ExerciseTitle                  = 0x0108,        // 264
    DiveSummary                    = 0x010C,        // 268
    Spo2Data                       = 0x010D,        // 269
    SleepLevel                     = 0x0113,        // 275
    Jump                           = 0x011D,        // 285
    AadAccelFeatures               = 0x0121,        // 289
    BeatIntervals                  = 0x0122,        // 290
    RespirationRate                = 0x0129,        // 297
    HsaAccelerometerData           = 0x012E,        // 302
    HsaStepData                    = 0x0130,        // 304
    HsaSpo2Data                    = 0x0131,        // 305
    HsaStressData                  = 0x0132,        // 306
    HsaRespirationData             = 0x0133,        // 307
    HsaHeartRateData               = 0x0134,        // 308
    Split                          = 0x0138,        // 312
    SplitSummary                   = 0x0139,        // 313
    HsaBodyBatteryData             = 0x013A,        // 314
    HsaEvent                       = 0x013B,        // 315
    ClimbPro                       = 0x013D,        // 317
    TankUpdate                     = 0x013F,        // 319
    TankSummary                    = 0x0143,        // 323
    SleepAssessment                = 0x015A,        // 346
    HrvStatusSummary               = 0x0172,        // 370
    HrvValue                       = 0x0173,        // 371
    RawBbi                         = 0x0174,        // 372
    DeviceAuxBatteryInfo           = 0x0177,        // 375
    HsaGyroscopeData               = 0x0178,        // 376
    ChronoShotSession              = 0x0183,        // 387
    ChronoShotData                 = 0x0184,        // 388
    HsaConfigurationData           = 0x0185,        // 389
    DiveApneaAlarm                 = 0x0189,        // 393
    SkinTempOvernight              = 0x018E,        // 398
    HsaWristTemperatureData        = 0x0199,        // 409
    SleepDisruptionSeverityPeriod  = 0x01D6,        // 470
    SleepDisruptionOvernightSeverity = 0x01D7,      // 471

    MfgRangeMin                    = 0xFF00,        // 0xFF00
    MfgRangeMax                    = 0xFFFE,        // 0xFFFE
    Invalid                        = 0xFFFF         // 65535
};

struct FixedHeader
{
    u8 reserved;
    Architecture architecture;
    MsgNum global_msg_num;
    u8 field_num;
};

fn clearScratchFixedHeader()
{
    scratch_fix_header.reserved = 0;
    scratch_fix_header.architecture = Architecture::BigEndian;
    scratch_fix_header.global_msg_num = MsgNum::Invalid;
    scratch_fix_header.field_num = 0;
};

fn copyFixedHeader(std::mem::Section _scratch, ref FixedHeader header)
{
    std::mem::copy_value_to_section(header, _scratch, fixed_header_addr);
};

fn clearScratchDefinitions(u16 limit = 256)
{
    for(u16 i=0, i<limit, i+=1)
    {
        scratch_defs[i].field_definition_num = 255;
        scratch_defs[i].size = 0;
        scratch_defs[i].field_base_type = 255; //255 is invalid for any enum u8
    }
};

fn copyDefinitions(std::mem::Section _scratch, ref auto defs, u16 field_num)
{
    for(u16 i=0, i<field_num, i+=1)
    {
        u32 item_addr  = defs_array_addr + i * sizeof(defs[i]);
        std::mem::copy_value_to_section(defs[i], _scratch, item_addr);
    }    
};

fn printDefinitions(ref auto defs, u16 field_num, str prefix)
{
    for(u16 i=0, i<field_num, i+=1)
    {
        std::print("{} FDN:{}", prefix, defs[i].field_definition_num);
    }
};

struct DataSizeBytes
{
    u8 data_size_lsb;
    u16 data_size;
    u8 data_size_msb;
};

struct DataSizeRecordLength
{
    u8 data_size_lsb;
    u24 length;
};

bitfield ProtocolVersion
{
    major : 4;
    minor : 4;
} [[bitfield_order(std::core::BitfieldOrder::MostToLeastSignificant, 8)]];

bitfield ProfileVersion
{
    major : 8;
    minor : 8;
} [[bitfield_order(std::core::BitfieldOrder::MostToLeastSignificant, 16)]];

struct Header
{
    u8 header_size;
    ProtocolVersion protocol_version_number;
    ProfileVersion protocol_version;    
    le u32 data_size;
    char data_type[4];
    if(prefetched_header_size == header_with_crc)
    {
        u8 crc_lsb;
        u8 crc_msb;
    }
};

enum MessageType : u8
{
    DefinitionMessage,
    DataMessage
};

bitfield RecordHeader {
    normal_header : 1;
    if(normal_header == 0)
    {
        message_type : 1; 
        message_type_specific : 1;
        reserved : 1;
        local_message_type : 4;       
    }
    else if (normal_header == 1)
    {
        local_message_type : 2;
        time_offset : 5;
    }
} [[bitfield_order(std::core::BitfieldOrder::MostToLeastSignificant, 8)]];

enum FileType : u8
{
    Device = 0x01,              //1
    Settings = 0x02,            //2
    Sport = 0x03,               //3
    Activity = 0x04,            //4
    Workout = 0x05,             //5
    Course = 0x06,              //6
    Schedules = 0x07,           //7
    Weight = 0x09,              //9
    Totals = 0x0A,              //10
    Goals = 0x0B,               //11
    BloodPressure = 0x0E,       //14
    MonitoringA = 0x0F,         //15
    ActivitySummary = 0x14,     //20
    MonitoringDaily = 0x1C,     //28
    MonitoringB = 0x20,         //32
    Segment = 0x22,             //34
    SegmentList = 0x24,         //36
    ExdConfiguration = 0x28,    //40
    MfgRangeMin = 0xF7,         //247
    MfgRangeMax = 0xFE,         //254
    Invalid = 0xFF              //255
};

enum TypeEnum : u8
{
    Enum                        = 0x00,
    Sint8                       = 0x01,
    Uint8                       = 0x02,
    Sint16                      = 0x03,
    Uint16                      = 0x04,
    Sint32                      = 0x05,
    Uint32                      = 0x06,
    String                      = 0x07,
    Float32                     = 0x08,
    Float64                     = 0x09,
    Uint8z                      = 0x0A,
    Uint16z                     = 0x0B,
    Uint32z                     = 0x0C,
    Byte                        = 0x0D,
    Sint64                      = 0x0E,
    Uint64                      = 0x0F,
    Uint64z                     = 0x10,
    Bool                        = 0x11,
    File                        = 0x12,
    MesgNum                     = 0x13,
    Checksum                    = 0x14,
    FileFlags                   = 0x15,
    MesgCount                   = 0x16,
    DateTime                    = 0x17,
    LocalDateTime               = 0x18,
    MessageIndex                = 0x19,
    DeviceIndex                 = 0x1A,
    Gender                      = 0x1B,
    Language                    = 0x1C,
    LanguageBits0               = 0x1D,
    LanguageBits1               = 0x1E,
    LanguageBits2               = 0x1F,
    LanguageBits3               = 0x20,
    LanguageBits4               = 0x21,
    TimeZone                    = 0x22,
    DisplayMeasure              = 0x23,
    DisplayHeart                = 0x24,
    DisplayPower                = 0x25,
    DisplayPosition             = 0x26,
    Switch                      = 0x27,
    Sport                       = 0x28,
    SportBits0                  = 0x29,
    SportBits1                  = 0x2A,
    SportBits2                  = 0x2B,
    SportBits3                  = 0x2C,
    SportBits4                  = 0x2D,
    SportBits5                  = 0x2E,
    SportBits6                  = 0x2F,
    SubSport                    = 0x30,
    SportEvent                  = 0x31,
    Activity                    = 0x32,
    Intensity                   = 0x33,
    SessionTrigger              = 0x34,
    AutolapTrigger              = 0x35,
    LapTrigger                  = 0x36,
    TimeMode                    = 0x37,
    BacklightMode               = 0x38,
    DateMode                    = 0x39,
    BacklightTimeout            = 0x3A,
    Event                       = 0x3B,
    EventType                   = 0x3C,
    TimerTrigger                = 0x3D,
    FitnessEquipmentState       = 0x3E,
    Tone                        = 0x3F,
    Autoscroll                  = 0x40,
    ActivityClass               = 0x41,
    HrZoneCalc                  = 0x42,
    PwrZoneCalc                 = 0x43,
    WktStepDuration             = 0x44,
    WktStepTarget               = 0x45,
    Goal                        = 0x46,
    GoalRecurrence              = 0x47,
    GoalSource                  = 0x48,
    Schedule                    = 0x49,
    CoursePoint                 = 0x4A,
    Manufacturer                = 0x4B,
    GarminProduct               = 0x4C,
    AntplusDeviceType           = 0x4D,
    AntNetwork                  = 0x4E,
    WorkoutCapabilities         = 0x4F,
    BatteryStatus               = 0x50,
    HrType                      = 0x51,
    CourseCapabilities          = 0x52,
    Weight                      = 0x53,
    WorkoutHr                   = 0x54,
    WorkoutPower                = 0x55,
    BpStatus                    = 0x56,
    UserLocalId                 = 0x57,
    SwimStroke                  = 0x58,
    ActivityType                = 0x59,
    ActivitySubtype             = 0x5A,
    ActivityLevel               = 0x5B,
    Side                        = 0x5C,
    LeftRightBalance            = 0x5D,
    LeftRightBalance100         = 0x5E,
    LengthType                  = 0x5F,
    DayOfWeek                   = 0x60,
    ConnectivityCapabilities    = 0x61,
    WeatherReport               = 0x62,
    WeatherStatus               = 0x63,
    WeatherSeverity             = 0x64,
    WeatherSevereType           = 0x65,
    TimeIntoDay                 = 0x66,
    LocaltimeIntoDay            = 0x67,
    StrokeType                  = 0x68,
    BodyLocation                = 0x69,
    SegmentLapStatus            = 0x6A,
    SegmentLeaderboardType      = 0x6B,
    SegmentDeleteStatus         = 0x6C,
    SegmentSelectionType        = 0x6D,
    SourceType                  = 0x6E,
    LocalDeviceType             = 0x6F,
    BleDeviceType               = 0x70,
    AntChannelId                = 0x71,
    DisplayOrientation          = 0x72,
    WorkoutEquipment            = 0x73,
    WatchfaceMode               = 0x74,
    DigitalWatchfaceLayout      = 0x75,
    AnalogWatchfaceLayout       = 0x76,
    RiderPositionType           = 0x77,
    PowerPhaseType              = 0x78,
    CameraEventType             = 0x79,
    SensorType                  = 0x7A,
    BikeLightNetworkConfigType  = 0x7B,
    CommTimeoutType             = 0x7C,
    CameraOrientationType       = 0x7D,
    AttitudeStage               = 0x7E,
    AttitudeValidity            = 0x7F,
    AutoSyncFrequency           = 0x80,
    ExdLayout                   = 0x81,
    ExdDisplayType              = 0x82,
    ExdDataUnits                = 0x83,
    ExdQualifiers               = 0x84,
    ExdDescriptors              = 0x85,
    AutoActivityDetect          = 0x86,
    SupportedExdScreenLayouts   = 0x87,
    FitBaseType                 = 0x88,
    TurnType                    = 0x89,
    BikeLightBeamAngleMode      = 0x8A,
    FitBaseUnit                 = 0x8B,
    SetType                     = 0x8C,
    MaxMetCategory              = 0x8D,
    ExerciseCategory            = 0x8E,
    BenchPressExerciseName      = 0x8F,
    CalfRaiseExerciseName       = 0x90,
    CardioExerciseName          = 0x91,
    CarryExerciseName           = 0x92,
    ChopExerciseName            = 0x93,
    CoreExerciseName            = 0x94,
    CrunchExerciseName          = 0x95,
    CurlExerciseName            = 0x96,
    DeadliftExerciseName        = 0x97,
    FlyeExerciseName            = 0x98,
    HipRaiseExerciseName        = 0x99,
    HipStabilityExerciseName    = 0x9A,
    HipSwingExerciseName        = 0x9B,
    HyperextensionExerciseName  = 0x9C,
    LateralRaiseExerciseName    = 0x9D,
    LegCurlExerciseName         = 0x9E,
    LegRaiseExerciseName        = 0x9F,
    LungeExerciseName           = 0xA0,
    OlympicLiftExerciseName     = 0xA1,
    PlankExerciseName           = 0xA2,
    PlyoExerciseName            = 0xA3,
    PullUpExerciseName          = 0xA4,
    PushUpExerciseName          = 0xA5,
    RowExerciseName             = 0xA6,
    ShoulderPressExerciseName   = 0xA7,
    ShoulderStabilityExerciseName = 0xA8,
    ShrugExerciseName           = 0xA9,
    SitUpExerciseName           = 0xAA,
    SquatExerciseName           = 0xAB,
    TotalBodyExerciseName       = 0xAC,
    MoveExerciseName            = 0xAD,
    PoseExerciseName            = 0xAE,
    TricepsExtensionExerciseName = 0xAF,
    WarmUpExerciseName          = 0xB0,
    RunExerciseName             = 0xB1,
    BikeExerciseName            = 0xB2,
    BandedExercisesExerciseName = 0xB3,
    BattleRopeExerciseName      = 0xB4,
    EllipticalExerciseName      = 0xB5,
    FloorClimbExerciseName      = 0xB6,
    IndoorBikeExerciseName      = 0xB7,
    IndoorRowExerciseName       = 0xB8,
    LadderExerciseName          = 0xB9,
    SandbagExerciseName         = 0xBA,
    SledExerciseName            = 0xBB,
    SledgeHammerExerciseName    = 0xBC,
    StairStepperExerciseName    = 0xBD,
    SuspensionExerciseName      = 0xBE,
    TireExerciseName            = 0xBF,
    BikeOutdoorExerciseName     = 0xC0,
    RunIndoorExerciseName       = 0xC1,
    WaterType                   = 0xC2,
    TissueModelType             = 0xC3,
    DiveGasStatus               = 0xC4,
    DiveAlert                   = 0xC5,
    DiveAlarmType               = 0xC6,
    DiveBacklightMode           = 0xC7,
    SleepLevel                  = 0xC8,
    Spo2MeasurementType         = 0xC9,
    CcrSetpointSwitchMode       = 0xCA,
    DiveGasMode                 = 0xCB,
    ProjectileType              = 0xCC,
    FaveroProduct               = 0xCD,
    SplitType                   = 0xCE,
    ClimbProEvent               = 0xCF,
    GasConsumptionRateType      = 0xD0,
    TapSensitivity              = 0xD1,
    RadarThreatLevelType        = 0xD2,
    SleepDisruptionSeverity     = 0xD3,
    MaxMetSpeedSource           = 0xD4,
    MaxMetHeartRateSource       = 0xD5,
    HrvStatus                   = 0xD6,
    NoFlyTimeMode               = 0xD7,

    Invalid                    = 0xD8
};

enum FieldBaseTypeEnum : u8
{
    Enum = 0x00,
    SInt8 = 0x01,
    UInt8 = 0x02,
    SInt16 = 0x03,
    UInt16 = 0x04,
    SInt32 = 0x05,
    UInt32 = 0x06,
    String = 0x07,
    Float32 = 0x08,
    Float64 = 0x09,
    UInt8z = 0x0A,
    UInt16z = 0x0B,
    UInt32z = 0x0C,
    Byte = 0x0D,
    SInt64 = 0x0E,
    UInt64 = 0x0F,
    UInt64z = 0x10,
    // And this with the type defn to get the index
    BaseTypeNumMask = 0x1F
};

// enum FitBaseTypeEnum : u8
// {
//     Enum        = 0x00,        // 0
//     Sint8       = 0x01,        // 1
//     Uint8       = 0x02,        // 2
//     Sint16      = 0x83,        // 131
//     Uint16      = 0x84,        // 132
//     Sint32      = 0x85,        // 133
//     Uint32      = 0x86,        // 134
//     String      = 0x07,        // 7
//     Float32     = 0x88,        // 136
//     Float64     = 0x89,        // 137
//     Uint8z      = 0x0A,        // 10
//     Uint16z     = 0x8B,        // 139
//     Uint32z     = 0x8C,        // 140
//     Byte        = 0x0D,        // 13
//     Sint64      = 0x8E,        // 142
//     Uint64      = 0x8F,        // 143
//     Uint64z     = 0x90,        // 144
//     Invalid     = 0xFF         // 0xFF
// } [[format("fit_base_type_formatter2")]];

enum FitBaseTypeEnum : u8
{
    Enum        = 0,
    Sint8       = 1,
    Uint8       = 2,
    Sint16      = 131,
    Uint16      = 132,
    Sint32      = 133,
    Uint32      = 134,
    String      = 7,
    Float32     = 136,
    Float64     = 137,
    Uint8z      = 10,
    Uint16z     = 139,
    Uint32z     = 140,
    Byte        = 13,
    Sint64      = 142,
    Uint64      = 143,
    Uint64z     = 144,
    Invalid     = 0xFF
} [[format("fit_base_type_formatter_2")]];

enum SportType : u8
{
    Generic = 0,
    Running = 1,
    Cycling = 2,
    Transition = 3,
    FitnessEquipment = 4,
    Swimming = 5,
    Basketball = 6,
    Soccer = 7,
    Tennis = 8,
    AmericanFootball = 9,
    Training = 10,
    Walking = 11,
    CrossCountrySkiing = 12,
    AlpineSkiing = 13,
    Snowboarding = 14,
    Rowing = 15,
    Mountaineering = 16,
    Hiking = 17,
    Multisport = 18,
    Paddling = 19,
    Flying = 20,
    EBiking = 21,
    Motorcycling = 22,
    Boating = 23,
    Driving = 24,
    Golf = 25,
    HangGliding = 26,
    HorsebackRiding = 27,
    Hunting = 28,
    Fishing = 29,
    InlineSkating = 30,
    RockClimbing = 31,
    Sailing = 32,
    IceSkating = 33,
    SkyDiving = 34,
    Snowshoeing = 35,
    Snowmobiling = 36,
    StandUpPaddleboarding = 37,
    Surfing = 38,
    Wakeboarding = 39,
    WaterSkiing = 40,
    Kayaking = 41,
    Rafting = 42,
    Windsurfing = 43,
    Kitesurfing = 44,
    Tactical = 45,
    Jumpmaster = 46,
    Boxing = 47,
    FloorClimbing = 48,
    Baseball = 49,
    Diving = 53,
    Hiit = 62,
    Racket = 64,
    WheelchairPushWalk = 65,
    WheelchairPushRun = 66,
    Meditation = 67,
    DiscGolf = 69,
    Cricket = 71,
    Rugby = 72,
    Hockey = 73,
    Lacrosse = 74,
    Volleyball = 75,
    WaterTubing = 76,
    Wakesurfing = 77,
    MixedMartialArts = 80,
    Snorkeling = 82,
    Dance = 83,
    JumpRope = 84,

    All = 254,
    Invalid = 255
};

enum SubSportType : u8
{
    Generic = 0,
    Treadmill = 1,
    Street = 2,
    Trail = 3,
    Track = 4,
    Spin = 5,
    IndoorCycling = 6,
    Road = 7,
    Mountain = 8,
    Downhill = 9,
    Recumbent = 10,
    Cyclocross = 11,
    HandCycling = 12,
    TrackCycling = 13,
    IndoorRowing = 14,
    Elliptical = 15,
    StairClimbing = 16,
    LapSwimming = 17,
    OpenWater = 18,
    FlexibilityTraining = 19,
    StrengthTraining = 20,
    WarmUp = 21,
    Match = 22,
    Exercise = 23,
    Challenge = 24,
    IndoorSkiing = 25,
    CardioTraining = 26,
    IndoorWalking = 27,
    EBikeFitness = 28,
    Bmx = 29,
    CasualWalking = 30,
    SpeedWalking = 31,
    BikeToRunTransition = 32,
    RunToBikeTransition = 33,
    SwimToBikeTransition = 34,
    Atv = 35,
    Motocross = 36,
    Backcountry = 37,
    Resort = 38,
    RcDrone = 39,
    Wingsuit = 40,
    Whitewater = 41,
    SkateSkiing = 42,
    Yoga = 43,
    Pilates = 44,
    IndoorRunning = 45,
    GravelCycling = 46,
    EBikeMountain = 47,
    Commuting = 48,
    MixedSurface = 49,
    Navigate = 50,
    TrackMe = 51,
    Map = 52,
    SingleGasDiving = 53,
    MultiGasDiving = 54,
    GaugeDiving = 55,
    ApneaDiving = 56,
    ApneaHunting = 57,
    VirtualActivity = 58,
    Obstacle = 59,
    Breathing = 62,
    SailRace = 65,
    Ultra = 67,
    IndoorClimbing = 68,
    Bouldering = 69,
    Hiit = 70,
    Amrap = 73,
    Emom = 74,
    Tabata = 75,
    Pickleball = 84,
    Padel = 85,
    IndoorWheelchairWalk = 86,
    IndoorWheelchairRun = 87,
    IndoorHandCycling = 88,
    Squash = 94,
    Badminton = 95,
    Racquetball = 96,
    TableTennis = 97,
    FlyCanopy = 110,
    FlyParaglide = 111,
    FlyParamotor = 112,
    FlyPressurized = 113,
    FlyNavigate = 114,
    FlyTimer = 115,
    FlyAltimeter = 116,
    FlyWx = 117,
    FlyVfr = 118,
    FlyIfr = 119,

    All = 254,
    Invalid = 255
};

enum FileIdFieldDefinitionType : u8
{
    Type = 0x00,
    Manufacturer = 0x01,
    Product = 0x02,
    SerialNumber = 0x03,
    TimeCreated = 0x04,
    Number = 0x05,
    ProductName = 0x08,
    Invalid = 0xFF
};

enum SessionFieldDefinitionType : u8
{
    Event = 0,
    EventType = 1,
    StartTime = 2,
    StartPositionLat = 3,
    StartPositionLong = 4,
    Sport = 5,
    SubSport = 6,
    TotalElapsedTime = 7,
    TotalTimerTime = 8,
    TotalDistance = 9,
    TotalCycles = 10,           //TotalStrides/TotalStrokes
    TotalCalories = 11,
    TotalFatCalories = 13,
    AvgSpeed = 14,
    MaxSpeed = 15,
    AvgHeartRate = 16,
    MaxHeartRate = 17,
    AvgCadence = 18,            //AvgRunningCadence
    MaxCadence = 19,            //MaxRunningCadence
    AvgPower = 20,
    MaxPower = 21,
    TotalAscent = 22,
    TotalDescent = 23,
    TotalTrainingEffect = 24,
    FirstLapIndex = 25,
    NumLaps = 26,
    EventGroup = 27,
    Trigger = 28,
    NecLat = 29,
    NecLong = 30,
    SwcLat = 31,
    SwcLong = 32,
    NumLengths = 33,
    NormalizedPower = 34,
    TrainingStressScore = 35,
    IntensityFactor = 36,
    LeftRightBalance = 37,
    EndPositionLat = 38,
    EndPositionLong = 39,
    AvgStrokeCount = 41,
    AvgStrokeDistance = 42,
    SwimStroke = 43,
    PoolLength = 44,
    ThresholdPower = 45,
    PoolLengthUnit = 46,
    NumActiveLengths = 47,
    TotalWork = 48,
    AvgAltitude = 49,
    MaxAltitude = 50,
    GpsAccuracy = 51,
    AvgGrade = 52,
    AvgPosGrade = 53,
    AvgNegGrade = 54,
    MaxPosGrade = 55,
    MaxNegGrade = 56,
    AvgTemperature = 57,
    MaxTemperature = 58,
    TotalMovingTime = 59,
    AvgPosVerticalSpeed = 60,
    AvgNegVerticalSpeed = 61,
    MaxPosVerticalSpeed = 62,
    MaxNegVerticalSpeed = 63,
    MinHeartRate = 64,
    TimeInHrZone = 65,
    TimeInSpeedZone = 66,
    TimeInCadenceZone = 67,
    TimeInPowerZone = 68,
    AvgLapTime = 69,
    BestLapIndex = 70,
    MinAltitude = 71,
    PlayerScore = 82,
    OpponentScore = 83,
    OpponentName = 84,
    StrokeCount = 85,
    ZoneCount = 86,
    MaxBallSpeed = 87,
    AvgBallSpeed = 88,
    AvgVerticalOscillation = 89,
    AvgStanceTimePercent = 90,
    AvgStanceTime = 91,
    AvgFractionalCadence = 92,
    MaxFractionalCadence = 93,
    TotalFractionalCycles = 94,
    AvgTotalHemoglobinConc = 95,
    MinTotalHemoglobinConc = 96,
    MaxTotalHemoglobinConc = 97,
    AvgSaturatedHemoglobinPercent = 98,
    MinSaturatedHemoglobinPercent = 99,
    MaxSaturatedHemoglobinPercent = 100,
    AvgLeftTorqueEffectiveness = 101,
    AvgRightTorqueEffectiveness = 102,
    AvgLeftPedalSmoothness = 103,
    AvgRightPedalSmoothness = 104,
    AvgCombinedPedalSmoothness = 105,
    SportProfileName = 110,
    SportIndex = 111,
    TimeStanding = 112,
    StandCount = 113,
    AvgLeftPco = 114,
    AvgRightPco = 115,
    AvgLeftPowerPhase = 116,
    AvgLeftPowerPhasePeak = 117,
    AvgRightPowerPhase = 118,
    AvgRightPowerPhasePeak = 119,
    AvgPowerPosition = 120,
    MaxPowerPosition = 121,
    AvgCadencePosition = 122,
    MaxCadencePosition = 123,
    EnhancedAvgSpeed = 124,
    EnhancedMaxSpeed = 125,
    EnhancedAvgAltitude = 126,
    EnhancedMinAltitude = 127,
    EnhancedMaxAltitude = 128,
    AvgLevMotorPower = 129,
    MaxLevMotorPower = 130,
    LevBatteryConsumption = 131,
    AvgVerticalRatio = 132,
    AvgStanceTimeBalance = 133,
    AvgStepLength = 134,
    TotalAnaerobicTrainingEffect = 137,
    AvgVam = 139,
    AvgDepth = 140,
    MaxDepth = 141,
    SurfaceInterval = 142,
    StartCns = 143,
    EndCns = 144,
    StartN2 = 145,
    EndN2 = 146,
    AvgRespirationRate = 147,
    MaxRespirationRate = 148,
    MinRespirationRate = 149,
    MinTemperature = 150,
    O2Toxicity = 155,
    DiveNumber = 156,
    TrainingLoadPeak = 168,
    EnhancedAvgRespirationRate = 169,
    EnhancedMaxRespirationRate = 170,
    EnhancedMinRespirationRate = 180,
    TotalGrit = 181,
    TotalFlow = 182,
    JumpCount = 183,
    AvgGrit = 186,
    AvgFlow = 187,
    WorkoutFeel = 192,
    WorkoutRpe = 193,
    AvgSpo2 = 194,
    AvgStress = 195,
    MetabolicCalories = 196,
    SdrrHrv = 197,
    RmssdHrv = 198,
    TotalFractionalAscent = 199,
    TotalFractionalDescent = 200,
    AvgCoreTemperature = 208,
    MinCoreTemperature = 209,
    MaxCoreTemperature = 210,
    Timestamp = 253,
    MessageIndex = 254,

    Invalid = 255
};

enum LapFieldDefinitionType : u8
{
    Event = 0,
    EventType = 1,
    StartTime = 2,
    StartPositionLat = 3,
    StartPositionLong = 4,
    EndPositionLat = 5,
    EndPositionLong = 6,
    TotalElapsedTime = 7,
    TotalTimerTime = 8,
    TotalDistance = 9,
    TotalCycles = 10,
    TotalCalories = 11,
    TotalFatCalories = 12,
    AvgSpeed = 13,
    MaxSpeed = 14,
    AvgHeartRate = 15,
    MaxHeartRate = 16,
    AvgCadence = 17,
    MaxCadence = 18,
    AvgPower = 19,
    MaxPower = 20,
    TotalAscent = 21,
    TotalDescent = 22,
    Intensity = 23,
    LapTrigger = 24,
    Sport = 25,
    EventGroup = 26,
    NumLengths = 32,
    NormalizedPower = 33,
    LeftRightBalance = 34,
    FirstLengthIndex = 35,
    AvgStrokeDistance = 37,
    SwimStroke = 38,
    SubSport = 39,
    NumActiveLengths = 40,
    TotalWork = 41,
    AvgAltitude = 42,
    MaxAltitude = 43,
    GpsAccuracy = 44,
    AvgGrade = 45,
    AvgPosGrade = 46,
    AvgNegGrade = 47,
    MaxPosGrade = 48,
    MaxNegGrade = 49,
    AvgTemperature = 50,
    MaxTemperature = 51,
    TotalMovingTime = 52,
    AvgPosVerticalSpeed = 53,
    AvgNegVerticalSpeed = 54,
    MaxPosVerticalSpeed = 55,
    MaxNegVerticalSpeed = 56,
    TimeInHrZone = 57,
    TimeInSpeedZone = 58,
    TimeInCadenceZone = 59,
    TimeInPowerZone = 60,
    RepetitionNum = 61,
    MinAltitude = 62,
    MinHeartRate = 63,
    WktStepIndex = 71,
    OpponentScore = 74,
    StrokeCount = 75,
    ZoneCount = 76,
    AvgVerticalOscillation = 77,
    AvgStanceTimePercent = 78,
    AvgStanceTime = 79,
    AvgFractionalCadence = 80,
    MaxFractionalCadence = 81,
    TotalFractionalCycles = 82,
    PlayerScore = 83,
    AvgTotalHemoglobinConc = 84,
    MinTotalHemoglobinConc = 85,
    MaxTotalHemoglobinConc = 86,
    AvgSaturatedHemoglobinPercent = 87,
    MinSaturatedHemoglobinPercent = 88,
    MaxSaturatedHemoglobinPercent = 89,
    AvgLeftTorqueEffectiveness = 91,
    AvgRightTorqueEffectiveness = 92,
    AvgLeftPedalSmoothness = 93,
    AvgRightPedalSmoothness = 94,
    AvgCombinedPedalSmoothness = 95,
    TimeStanding = 98,
    StandCount = 99,
    AvgLeftPco = 100,
    AvgRightPco = 101,
    AvgLeftPowerPhase = 102,
    AvgLeftPowerPhasePeak = 103,
    AvgRightPowerPhase = 104,
    AvgRightPowerPhasePeak = 105,
    AvgPowerPosition = 106,
    MaxPowerPosition = 107,
    AvgCadencePosition = 108,
    MaxCadencePosition = 109,
    EnhancedAvgSpeed = 110,
    EnhancedMaxSpeed = 111,
    EnhancedAvgAltitude = 112,
    EnhancedMinAltitude = 113,
    EnhancedMaxAltitude = 114,
    AvgLevMotorPower = 115,
    MaxLevMotorPower = 116,
    LevBatteryConsumption = 117,
    AvgVerticalRatio = 118,
    AvgStanceTimeBalance = 119,
    AvgStepLength = 120,
    AvgVam = 121,
    AvgDepth = 122,
    MaxDepth = 123,
    MinTemperature = 124,
    EnhancedAvgRespirationRate = 136,
    EnhancedMaxRespirationRate = 137,
    AvgRespirationRate = 147,
    MaxRespirationRate = 148,
    TotalGrit = 149,
    TotalFlow = 150,
    JumpCount = 151,
    AvgGrit = 153,
    AvgFlow = 154,
    TotalFractionalAscent = 156,
    TotalFractionalDescent = 157,
    AvgCoreTemperature = 158,
    MinCoreTemperature = 159,
    MaxCoreTemperature = 160,
    Timestamp = 253,
    MessageIndex = 254,

    Invalid = 255
};

enum LapTriggerType : u8
{
    Manual = 0,
    Time = 1,
    Distance = 2,
    PositionStart = 3,
    PositionLap = 4,
    PositionWaypoint = 5,
    PositionMarked = 6,
    SessionEnd = 7,
    FitnessEquipment = 8,
    Invalid = 255
};

enum IntensityType : u8
{
    Active = 0,
    Rest = 1,
    Warmup = 2,
    Cooldown = 3,
    Recovery = 4,
    Interval = 5,
    Other = 6,
    Invalid = 255
};

enum ActivityFieldDefinitionType : u8
{
    TotalTimerTime = 0,
    NumSessions = 1,
    Type = 2,
    Event = 3,
    EventType = 4,
    LocalTimestamp = 5,
    EventGroup = 6,
    Timestamp = 253,
    Invalid = 255
};

bitfield CompressedSpeedDistanceBitField
{
    speed : 12;
    distance : 12;
};

enum DeviceIndexType : u8
{
    Creator = 0,
    Invalid = 0xFF
};

enum LeftRightBalanceType : u8
{
    Mask = 0x3FFF,
    Right = 0x8000,
    Invalid = 0xFFFF
};

enum StrokeType : u8
{
    NoEvent = 0,
    Other = 1,
    Serve = 2,
    Forehand = 3,
    Backhand = 4,
    Smash = 5,
    Invalid = 0xFF
};

enum ActivityType : u8
{
    Generic = 0,
    Running = 1,
    Cycling = 2,
    Transition = 3,
    FitnessEquipment = 4,
    Swimming = 5,
    Walking = 6,
    Sedentary = 8,
    All = 254,
    Invalid = 255
};

enum RecordFieldDefinitionType : u8
{
    PositionLat = 0,
    PositionLong = 1,
    Altitude = 2,
    HeartRate = 3,
    Cadence = 4,
    Distance = 5,
    Speed = 6,
    Power = 7,
    CompressedSpeedDistance = 8,
    Grade = 9,
    Resistance = 10,
    TimeFromCourse = 11,
    CycleLength = 12,
    Temperature = 13,
    Speed1s = 17,
    Cycles = 18,
    TotalCycles = 19,
    CompressedAccumulatedPower = 28,
    AccumulatedPower = 29,
    LeftRightBalance = 30,
    GpsAccuracy = 31,
    VerticalSpeed = 32,
    Calories = 33,
    VerticalOscillation = 39,
    StanceTimePercent = 40,
    StanceTime = 41,
    ActivityType = 42,
    LeftTorqueEffectiveness = 43,
    RightTorqueEffectiveness = 44,
    LeftPedalSmoothness = 45,
    RightPedalSmoothness = 46,
    CombinedPedalSmoothness = 47,
    Time128 = 48,
    StrokeType = 49,
    Zone = 50,
    BallSpeed = 51,
    Cadence256 = 52,
    FractionalCadence = 53,
    TotalHemoglobinConc = 54,
    TotalHemoglobinConcMin = 55,
    TotalHemoglobinConcMax = 56,
    SaturatedHemoglobinPercent = 57,
    SaturatedHemoglobinPercentMin = 58,
    SaturatedHemoglobinPercentMax = 59,
    DeviceIndex = 62,
    LeftPco = 67,
    RightPco = 68,
    LeftPowerPhase = 69,
    LeftPowerPhasePeak = 70,
    RightPowerPhase = 71,
    RightPowerPhasePeak = 72,
    EnhancedSpeed = 73,
    EnhancedAltitude = 78,
    BatterySoc = 81,
    MotorPower = 82,
    VerticalRatio = 83,
    StanceTimeBalance = 84,
    StepLength = 85,
    CycleLength16 = 87,
    AbsolutePressure = 91,
    Depth = 92,
    NextStopDepth = 93,
    NextStopTime = 94,
    TimeToSurface = 95,
    NdlTime = 96,
    CnsLoad = 97,
    N2Load = 98,
    RespirationRate = 99,
    EnhancedRespirationRate = 108,
    Grit = 114,
    Flow = 115,
    CurrentStress = 116,
    EbikeTravelRange = 117,
    EbikeBatteryLevel = 118,
    EbikeAssistMode = 119,
    EbikeAssistLevelPercent = 120,
    AirTimeRemaining = 123,
    PressureSac = 124,
    VolumeSac = 125,
    Rmv = 126,
    AscentRate = 127,
    Po2 = 129,
    CoreTemperature = 139,

    Timestamp = 253,

    Invalid = 255
};

struct FieldDefinition
{
    MsgNum dt = scratch_fix_header.global_msg_num;
#ifdef DEBUG_MODE
    try{
#endif
        match(dt)
        {
            (MsgNum::FileId): FileIdFieldDefinitionType field_definition_num;
            (MsgNum::Session): SessionFieldDefinitionType field_definition_num;
            (MsgNum::Lap): LapFieldDefinitionType field_definition_num;
            (MsgNum::Activity): ActivityFieldDefinitionType field_definition_num;
            (MsgNum::Record): RecordFieldDefinitionType field_definition_num;
            (_): u8 field_definition_num;
        }
#ifdef DEBUG_MODE
    }
    catch{}
#endif
    
    u8 size;
    FitBaseTypeEnum field_base_type;
};

fn field_definition_num_formatter(u8 fdn)
{
    match(scratch_fix_header.global_msg_num)
    {
        (MsgNum::FileId): {
            FileIdFieldDefinitionType fdt = fdn;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Activity): {
            ActivityFieldDefinitionType fdt = fdn;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Session): {
            SessionFieldDefinitionType fdt = fdn;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Lap): {
            LapFieldDefinitionType fdt = fdn;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Record): {
            RecordFieldDefinitionType fdt = fdn;
            return std::format("{}", std::string::to_string(fdt));
        }
        (_): return "Invalid MsgNum";
    }    
};

fn field_definition_num_formatter2(FieldDefinition def)
{
    match(def.dt)
    {
        (MsgNum::FileId): 
        {
            FileIdFieldDefinitionType fdt = def.field_definition_num;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Activity): 
        {
            ActivityFieldDefinitionType fdt = def.field_definition_num;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Session): 
        {
            SessionFieldDefinitionType fdt = def.field_definition_num;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Lap): 
        {
            LapFieldDefinitionType fdt = def.field_definition_num;
            return std::format("{}", std::string::to_string(fdt));
        }
        (MsgNum::Record): 
        {
            RecordFieldDefinitionType fdt = def.field_definition_num;
            return std::format("{}", std::string::to_string(fdt));
        }
        (_): return "Invalid MsgNum";
    }  
};

struct DefinitionMessage
{
#ifdef DEBUG_MODE
    try
    {
#endif
        clearScratchDefinitions(scratch_fix_header.field_num);
        clearScratchFixedHeader();
        
        FixedHeader fix_header; 
        copyFixedHeader(scratch, fix_header);
        FieldDefinition defs[fix_header.field_num];
        copyDefinitions(scratch, defs, fix_header.field_num);
#ifdef DEBUG_MODE
    }
    catch{
        break;
    }
#endif
};

enum EventType : u8
{
    Start = 0,
    Stop = 1,
    ConsecutiveDepreciated = 2,
    Marker = 3,
    StopAll = 4,
    BeginDepreciated = 5,
    EndDepreciated = 6,
    EndAllDepreciated = 7,
    StopDisable = 8,
    StopDisableAll = 9
};

enum Event : u8
{
    Timer = 0,
    Workout = 3,
    WorkoutStep = 4,
    PowerDown = 5,
    PowerUp = 6,
    OffCourse = 7,
    Session = 8,
    Lap = 9,
    CoursePoint = 10,
    Battery = 11,
    VirtualPartnerPace = 12,
    HrHighAlert = 13,
    HrLowAlert = 14,
    SpeedHighAlert = 15,
    SpeedLowAlert = 16,
    CadHighAlert = 17,
    CadLowAlert = 18,
    PowerHighAlert = 19,
    PowerLowAlert = 20,
    RecoveryHr = 21,
    BatteryLow = 22,
    TimeDurationAlert = 23,
    DistanceDurationAlert = 24,
    CalorieDurationAlert = 25,
    Activity = 26,
    FitnessEquipment = 27,
    Length = 28,
    UserMarker = 32,
    SportPoint = 33,
    Calibration = 36,
    FrontGearChange = 42,
    RearGearChange = 43,
    RiderPositionChange = 44,
    ElevHighAlert = 45,
    ElevLowAlert = 46,
    CommTimeout = 47,
    AutoActivityDetect = 54,
    DiveAlert = 56,
    DiveGasSwitched = 57,
    TankPressureReserve = 71,
    TankPressureCritical = 72,
    TankLost = 73,
    RadarThreatAlert = 75,
    TankBatteryLow = 76,
    TankPodConnected = 81,
    TankPodDisconnected = 82,

    Timestamp = 253,
    MessageIndex = 254,

    Invalid = 255
};

struct ActivityField
{
    auto i = std::core::array_index();
    auto s = scratch_defs[i].size;
    auto p = $;
    u8 fdn = u8(scratch_defs[i].field_definition_num);
    match (fdn)
    {
        (ActivityFieldDefinitionType::Timestamp): {
            if(scratch_fix_header.architecture == Architecture::BigEndian){
                be DateTime timestamp @ p [[format("format_datetime")]];
            }
            else
            {
                le DateTime timestamp @ p [[format("format_datetime")]];
            }
            scratch_time_created = time_created;
        }
        (ActivityFieldDefinitionType::TotalTimerTime): 
        {
            u32 total_timer_time;
        }
        (ActivityFieldDefinitionType::NumSessions): 
        {
            u16 num_sessions;
        }
        (ActivityFieldDefinitionType::Type): 
        {
            FileType type;
        }
        (ActivityFieldDefinitionType::Event): 
        {
            Event event;
        }
        (ActivityFieldDefinitionType::EventType):
        {
            EventType event_type;
        }
        (ActivityFieldDefinitionType::LocalTimestamp): 
        {
            if(scratch_fix_header.architecture == Architecture::BigEndian){
                be LocalDateTime local_timestamp [[format("format_local_datetime")]];
            }
            else
            {
                le LocalDateTime local_timestamp [[format("format_local_datetime")]];
            }
        }
        (ActivityFieldDefinitionType::EventGroup): 
        {
            u8 event_group;
        }
    }
    $ += s;
};

enum MessageIndexType : u8
{
    Selected = 0x8000,
    Reserved = 0x7000,
    Mask = 0x0FFF
};

enum SessionTriggerType : u8
{
    ActivityEnd = 0,
    Manual = 1,
    AutoMultiSport = 2,
    FitnessEquipment = 3
};

enum DisplayMeasureType : u8
{
    Metric = 0,
    Statute = 1,
    Nautical = 2
};

enum SwimStrokeType : u8
{
    Freestyle = 0,
    Backstroke = 1,
    Breaststroke = 2,
    Butterfly = 3,
    Drill = 4,
    Mixed = 5,
    IM = 6,
    IMByRound = 7,
    ReversedIMOrder = 8
};

enum LeftRightBalance100Type : u16
{
    Mask = 0x3FFF,
    Right = 0x8000
};

struct SessionField
{  
    auto i = std::core::array_index();
    auto s = scratch_defs[i].size;
    auto p = $;
    match (scratch_defs[i].field_definition_num) 
    {
        (SessionFieldDefinitionType::MessageIndex): 
        {
            MessageIndexType message_index @ p;
        }
        
        (SessionFieldDefinitionType::Timestamp): 
        {
            DateTime timestamp @ p [[format("format_datetime")]];
        }
        
        (SessionFieldDefinitionType::Event): {
            Event event @ p;
        }
        
        (SessionFieldDefinitionType::EventType): {
            EventType event_type @ p;
        }
        
        (SessionFieldDefinitionType::StartTime): 
        {
            DateTime start_time @ p;
        }
        
        (SessionFieldDefinitionType::StartPositionLat): 
        {
            s32 start_position_lat @ p;
        }
        
        (SessionFieldDefinitionType::StartPositionLong): 
        {
            s32 start_position_long @ p;
        }
        
        (SessionFieldDefinitionType::Sport): {
            SportType sport @ p;
        }
        
        (SessionFieldDefinitionType::SubSport): {
            SubSportType sub_sport @ p;
        }
        
        (SessionFieldDefinitionType::TotalElapsedTime): 
        {
            u32 total_elapsed_time @ p;
        }
        
        (SessionFieldDefinitionType::TotalTimerTime): 
        {
            u32 total_timer_time @ p;
        }
        
        (SessionFieldDefinitionType::TotalDistance): 
        {
            u32 total_distance @ p;
        }
        
        (SessionFieldDefinitionType::TotalCycles): 
        {
            u32 total_cycles @ p;
        }
        
        (SessionFieldDefinitionType::TotalCalories):
        {
            u16 total_calories @ p;
        }
        
        (SessionFieldDefinitionType::TotalFatCalories):
        {
            u16 total_fat_calories @ p;
        }
        
        (SessionFieldDefinitionType::AvgSpeed):
        {
            u16 avg_speed @ p;
        }
        
        (SessionFieldDefinitionType::MaxSpeed):
        {
            u16 max_speed @ p;
        }
        
        (SessionFieldDefinitionType::AvgHeartRate):
        {
            u8 avg_heart_rate @ p;
        }
        
        (SessionFieldDefinitionType::MaxHeartRate):
        {
            u8 max_heart_rate @ p;
        }
        
        (SessionFieldDefinitionType::AvgCadence):
        {
            u8 avg_cadence @ p;
        }
        
        (SessionFieldDefinitionType::MaxCadence):
        {
            u8 max_cadence @ p;
        }
        
        (SessionFieldDefinitionType::AvgPower):
        {
            u16 avg_power @ p;
        }
        
        (SessionFieldDefinitionType::MaxPower):
        {
            u16 max_power @ p;
        }
        
        (SessionFieldDefinitionType::TotalAscent):
        {
            u16 total_ascent @ p;
        }
        
        (SessionFieldDefinitionType::TotalDescent):
        {
            u16 total_descent @ p;
        }
        
        (SessionFieldDefinitionType::TotalTrainingEffect):
        {
            u8 total_training_effect @ p;
        }
        
        (SessionFieldDefinitionType::FirstLapIndex):
        {
            u16 first_lap_index @ p;
        }
        
        (SessionFieldDefinitionType::NumLaps):
        {
            u16 num_laps @ p;
        }
        
        (SessionFieldDefinitionType::EventGroup):
        {
            u8 event_group @ p;
        }
        
        (SessionFieldDefinitionType::Trigger):
        {
            SessionTriggerType session_trigger @ p;
        }
        
        (SessionFieldDefinitionType::NecLat):
        {
            s32 nec_lat @ p;
        }
        
        (SessionFieldDefinitionType::NecLong):
        {
            s32 nec_long @ p;
        }
        
        (SessionFieldDefinitionType::SwcLat):
        {
            s32 swc_lat @ p;
        }
        
        (SessionFieldDefinitionType::SwcLong):
        {
            s32 swc_long @ p;
        }
        
        (SessionFieldDefinitionType::NumLengths):
        {
            u16 num_lengths @ p;
        }
        
        (SessionFieldDefinitionType::NormalizedPower):
        {
            u16 normalized_power @ p;
        }
        
        (SessionFieldDefinitionType::TrainingStressScore):
        {
            u16 training_stress_score @ p;
        }
        
        (SessionFieldDefinitionType::IntensityFactor):
        {
            u16 intensity_factor @ p;
        }
        
        (SessionFieldDefinitionType::LeftRightBalance):
        {
            LeftRightBalance100Type left_right_balance @ p;
        }
        
        (SessionFieldDefinitionType::EndPositionLat):
        {
            s32 end_position_lat @ p;
        }
        
        (SessionFieldDefinitionType::EndPositionLong):
        {
            s32 end_position_long @ p;
        }
        
        (SessionFieldDefinitionType::AvgStrokeCount):
        {
            u32 avg_stroke_count @ p;
        }
        
        (SessionFieldDefinitionType::AvgStrokeDistance):
        {
            u16 avg_stroke_distance @ p;
        }
        
        (SessionFieldDefinitionType::SwimStroke):
        {
            SwimStrokeType swim_stroke @ p;
        }
        
        (SessionFieldDefinitionType::PoolLength):
        {
            u16 pool_length @ p;
        }
        
        (SessionFieldDefinitionType::ThresholdPower):
        {
            u16 threshold_power @ p;
        }
        
        (SessionFieldDefinitionType::NumActiveLengths):
        {
            u16 num_active_lengths @ p;
        }
        
        (SessionFieldDefinitionType::TotalWork):
        {
            u32 total_work @ p;
        }
        
        (SessionFieldDefinitionType::AvgAltitude):
        {
            u16 avg_altitude @ p;
        }
        
        (SessionFieldDefinitionType::MaxAltitude):
        {
            u16 max_altitude @ p;
        }
        
        (SessionFieldDefinitionType::GpsAccuracy):
        {
            u8 gps_accuracy @ p;
        }
        
        (SessionFieldDefinitionType::AvgGrade):
        {
            s16 avg_grade @ p;
        }
        
        (SessionFieldDefinitionType::AvgPosGrade):
        {
            s16 avg_pos_grade @ p;
        }
        
        (SessionFieldDefinitionType::AvgNegGrade):
        {
            s16 avg_neg_grade @ p;
        }
        
        (SessionFieldDefinitionType::MaxPosGrade):
        {
            s16 max_pos_grade @ p;
        }
        
        (SessionFieldDefinitionType::MaxNegGrade):
        {
            s16 max_neg_grade @ p;
        }
        
        (SessionFieldDefinitionType::AvgTemperature):
        {
            s8 avg_temperature @ p;
        }
        
        (SessionFieldDefinitionType::MaxTemperature):
        {
            s8 max_temperature @ p;
        }
        
        (SessionFieldDefinitionType::TotalMovingTime):
        {
            u32 total_moving_time @ p;
        }
        
        (SessionFieldDefinitionType::AvgPosVerticalSpeed):
        {
            s16 avg_pos_vertical_speed @ p;
        }
        
        (SessionFieldDefinitionType::AvgNegVerticalSpeed):
        {
            s16 avg_neg_vertical_speed @ p;
        }
        
        (SessionFieldDefinitionType::MaxPosVerticalSpeed):
        {
            s16 max_pos_vertical_speed @ p;
        }
        
        (SessionFieldDefinitionType::MaxNegVerticalSpeed):
        {
            s16 max_neg_vertical_speed @ p;
        }
        
        (SessionFieldDefinitionType::MinHeartRate):
        {
            u8 min_heart_rate @ p;
        }
        
        (SessionFieldDefinitionType::TimeInHrZone):
        {
            u32 time_in_hr_zone @ p;
        }
        
        (SessionFieldDefinitionType::TimeInSpeedZone):
        {
            u32 time_in_speed_zone @ p;
        }
        
        (SessionFieldDefinitionType::TimeInCadenceZone):
        {
            u32 time_in_cadence_zone @ p;
        }
        
        (SessionFieldDefinitionType::TimeInPowerZone):
        {
            u32 time_in_power_zone @ p;
        }
        
        (SessionFieldDefinitionType::AvgLapTime):
        {
            u32 avg_lap_time @ p;
        }
        
        (SessionFieldDefinitionType::BestLapIndex):
        {
            u16 best_lap_index @ p;
        }
        
        (SessionFieldDefinitionType::MinAltitude):
        {
            u16 min_altitude @ p;
        }
        
        (SessionFieldDefinitionType::PlayerScore):
        {
            u16 player_score @ p;
        }
        
        (SessionFieldDefinitionType::OpponentScore):
        {
            u16 opponent_score @ p;
        }
        
        (SessionFieldDefinitionType::OpponentName):
        {
            str opponent_name @ p;
        }
        
        (SessionFieldDefinitionType::StrokeCount):
        {
            u16 stroke_count @ p;
        }
        
        (SessionFieldDefinitionType::ZoneCount):
        {
            u16 zone_count @ p;
        }
        
        (SessionFieldDefinitionType::MaxBallSpeed):
        {
            u16 max_ball_speed @ p;
        }
        
        (SessionFieldDefinitionType::AvgBallSpeed):
        {
            u16 avg_ball_speed @ p;
        }
        
        (SessionFieldDefinitionType::AvgVerticalOscillation):
        {
            u16 avg_vertical_oscillation @ p;
        }
        
        (SessionFieldDefinitionType::AvgStanceTimePercent):
        {
            u16 avg_stance_time_percent @ p;
        }
        
        (SessionFieldDefinitionType::AvgStanceTime):
        {
            u16 avg_stance_time @ p;
        }
        
        (SessionFieldDefinitionType::AvgFractionalCadence):
        {
            u8 avg_fractional_cadence @ p;
        }
        
        (SessionFieldDefinitionType::MaxFractionalCadence):
        {
            u8 max_fractional_cadence @ p;
        }
        
        (SessionFieldDefinitionType::TotalFractionalCycles):
        {
            u8 total_fractional_cycles @ p;
        }
        
        (SessionFieldDefinitionType::AvgTotalHemoglobinConc):
        {
            u16 avg_total_hemoglobin_conc @ p;
        }
        
        (SessionFieldDefinitionType::MinTotalHemoglobinConc):
        {
            u16 min_total_hemoglobin_conc @ p;
        }
        
        (SessionFieldDefinitionType::MaxTotalHemoglobinConc):
        {
            u16 max_total_hemoglobin_conc @ p;
        }
        
        (SessionFieldDefinitionType::AvgSaturatedHemoglobinPercent):
        {
            u16 avg_saturated_hemoglobin_percent @ p;
        }
        
        (SessionFieldDefinitionType::MinSaturatedHemoglobinPercent):
        {
            u16 min_saturated_hemoglobin_percent @ p;
        }
        
        (SessionFieldDefinitionType::MaxSaturatedHemoglobinPercent):
        {
            u16 max_saturated_hemoglobin_percent @ p;
        }
        
        (SessionFieldDefinitionType::AvgLeftTorqueEffectiveness):
        {
            u8 avg_left_torque_effectiveness @ p;
        }
        
        (SessionFieldDefinitionType::AvgRightTorqueEffectiveness):
        {
            u8 avg_right_torque_effectiveness @ p;
        }
        
        (SessionFieldDefinitionType::AvgLeftPedalSmoothness):
        {
            u8 avg_left_pedal_smoothness @ p;
        }
        
        (SessionFieldDefinitionType::AvgRightPedalSmoothness):
        {
            u8 avg_left_pedal_smoothness @ p;
        }
        
        (SessionFieldDefinitionType::AvgCombinedPedalSmoothness):
        {
            u8 avg_combined_pedal_smoothness @ p;
        }
        
        (SessionFieldDefinitionType::SportProfileName):
        {
            str sport_profile_name @ p;
        }
        
        (SessionFieldDefinitionType::SportIndex):
        {
            u8 sport_index @ p;
        }
        
        (SessionFieldDefinitionType::TimeStanding):
        {
            u32 time_standing @ p;
        }
        
        (SessionFieldDefinitionType::StandCount):
        {
            u16 stand_count @ p;
        }
        
        (SessionFieldDefinitionType::AvgLeftPco):
        {
            s8 avg_left_pco @ p;
        }
        
        (SessionFieldDefinitionType::AvgRightPco):
        {
            s8 avg_right_pco @ p;
        }
        
        (SessionFieldDefinitionType::AvgLeftPowerPhase):
        {
            u8 avg_left_power_phase @ p;
        }
        
        (SessionFieldDefinitionType::AvgLeftPowerPhasePeak):
        {
            u8 avg_left_power_phase_peak @ p;
        }
        
        (SessionFieldDefinitionType::AvgRightPowerPhase):
        {
            u8 avg_right_power_phase @ p;
        }
        
        (SessionFieldDefinitionType::AvgRightPowerPhasePeak):
        {
            u8 avg_right_power_phase_peak @ p;
        }
        
        (SessionFieldDefinitionType::AvgPowerPosition):
        {
            u16 avg_power_position @ p;
        }
        
        (SessionFieldDefinitionType::MaxPowerPosition):
        {
            u16 max_power_position @ p;
        }
        
        (SessionFieldDefinitionType::AvgCadencePosition):
        {
            u8 avg_cadence_position @ p;
        }
        
        (SessionFieldDefinitionType::MaxCadencePosition):
        {
            u8 max_cadence_position @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedAvgSpeed):
        {
            u32 enhanced_avg_speed @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedMaxSpeed):
        {
            u32 enhanced_max_speed @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedAvgAltitude):
        {
            u32 enhanced_avg_altitude @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedMinAltitude):
        {
            u32 enhanced_min_altitude @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedMaxAltitude):
        {
            u32 enhanced_max_altitude @ p;
        }
        
        (SessionFieldDefinitionType::AvgLevMotorPower):
        {
            u16 avg_lev_motor_power @ p;
        }
        
        (SessionFieldDefinitionType::MaxLevMotorPower):
        {
            u16 max_lev_motor_power @ p;
        }
        
        (SessionFieldDefinitionType::LevBatteryConsumption):
        {
            u8 lev_battery_consumption @ p;
        }
        
        (SessionFieldDefinitionType::AvgVerticalRatio):
        {
            u16 avg_vertical_ratio @ p;
        }
        
        (SessionFieldDefinitionType::AvgStanceTimeBalance):
        {
            u16 avg_stance_time_balance @ p;
        }
        
        (SessionFieldDefinitionType::AvgStepLength):
        {
            u16 avg_step_length @ p;
        }
        
        (SessionFieldDefinitionType::TotalAnaerobicTrainingEffect):
        {
            u8 total_anaerobic_training_effect @ p;
        }
        
        (SessionFieldDefinitionType::AvgVam):
        {
            u16 avg_vam @ p;
        }
        
        (SessionFieldDefinitionType::AvgDepth):
        {
            u32 avg_depth @ p;
        }
        
        (SessionFieldDefinitionType::MaxDepth):
        {
            u32 max_depth @ p;
        }
        
        (SessionFieldDefinitionType::SurfaceInterval):
        {
            u32 surface_interval @ p;
        }
        
        (SessionFieldDefinitionType::StartCns):
        {
            u8 start_cns @ p;
        }
        
        (SessionFieldDefinitionType::EndCns):
        {
            u8 end_cns @ p;
        }
        
        (SessionFieldDefinitionType::StartN2):
        {
            u16 start_n2 @ p;
        }
        
        (SessionFieldDefinitionType::EndN2):
        {
            u16 end_n2 @ p;
        }
        
        (SessionFieldDefinitionType::AvgRespirationRate):
        {
            u8 avg_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::MaxRespirationRate):
        {
            u8 max_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::MinRespirationRate):
        {
            u8 min_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::MinTemperature):
        {
            s8 min_temperature @ p;
        }
        
        (SessionFieldDefinitionType::O2Toxicity):
        {
            u16 o2_toxicity @ p;
        }
        
        (SessionFieldDefinitionType::DiveNumber):
        {
            u32 dive_number @ p;
        }
        
        (SessionFieldDefinitionType::TrainingLoadPeak):
        {
            s32 training_load_peak @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedAvgRespirationRate):
        {
            u16 enhanced_avg_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedMaxRespirationRate):
        {
            u16 enhanced_max_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::EnhancedMinRespirationRate):
        {
            u16 enhanced_min_respiration_rate @ p;
        }
        
        (SessionFieldDefinitionType::TotalGrit):
        {
            float total_grit @ p;
        }
        
        (SessionFieldDefinitionType::TotalFlow):
        {
            float total_flow @ p;
        }
        
        (SessionFieldDefinitionType::JumpCount):
        {
            u16 jump_count @ p;
        }
        
        (SessionFieldDefinitionType::AvgGrit):
        {
            float avg_grit @ p;
        }
        
        (SessionFieldDefinitionType::AvgFlow):
        {
            float avg_flow @ p;
        }
        
        (SessionFieldDefinitionType::WorkoutFeel):
        {
            u8 workout_feel @ p;
        }
        
        (SessionFieldDefinitionType::WorkoutRpe):
        {
            u8 workout_rpe @ p;
        }
        
        (SessionFieldDefinitionType::AvgSpo2):
        {
            u8 avg_spo2 @ p;
        }
        
        (SessionFieldDefinitionType::AvgStress):
        {
            u8 avg_stress @ p;
        }
        
        (SessionFieldDefinitionType::MetabolicCalories):
        {
            u16 metabolic_calories @ p;
        }
        
        (SessionFieldDefinitionType::SdrrHrv):
        {
            u8 sdrr_hrv @ p;
        }
        
        (SessionFieldDefinitionType::RmssdHrv):
        {
            u8 rmssd_hrv @ p;
        }
        
        (SessionFieldDefinitionType::TotalFractionalAscent):
        {
            u8 total_fractional_ascent @ p;
        }
        
        (SessionFieldDefinitionType::TotalFractionalDescent):
        {
            u8 total_fractional_descent @ p;
        }
        
        (SessionFieldDefinitionType::AvgCoreTemperature):
        {
            u16 avg_core_temperature @ p;
        }
        
        (SessionFieldDefinitionType::MinCoreTemperature):
        {
            u16 min_core_temperature @ p;
        }
        
        (SessionFieldDefinitionType::MaxCoreTemperature):
        {
            u16 max_core_temperature @ p;
        }
    }
    $ += s;
};

struct LapField
{
    auto i = std::core::array_index();
    auto s = scratch_defs[i].size;
    auto p = $;
    match (scratch_defs[i].field_definition_num) 
    {
        (LapFieldDefinitionType::Event):
        {
            Event event @ p;
        }
        (LapFieldDefinitionType::EventType):
        {
            EventType event_type @ p;
        }
        (LapFieldDefinitionType::StartTime):
        {
            DateTime start_time @ p[[format("format_datetime")]];
        }
        (LapFieldDefinitionType::StartPositionLat):
        {
            s32 start_position_lat @ p;
        }
        (LapFieldDefinitionType::StartPositionLong):
        {
            s32 start_position_long @ p;
        }
        (LapFieldDefinitionType::EndPositionLat):
        {
            s32 end_position_lat @ p;
        }
        (LapFieldDefinitionType::EndPositionLong):
        {
            s32 end_position_long @ p;
        }
        (LapFieldDefinitionType::TotalElapsedTime):
        {
            u32 total_elapsed_time @ p;
        }
        (LapFieldDefinitionType::TotalTimerTime):
        {
            u32 total_timer_time @ p;
        }
        (LapFieldDefinitionType::TotalDistance):
        {
            u32 total_distance @ p;
        }
        (LapFieldDefinitionType::TotalCycles):
        {
            u32 total_cycles @ p;
        }
        (LapFieldDefinitionType::TotalCalories):
        {
            u16 total_calories @ p;
        }
        (LapFieldDefinitionType::TotalFatCalories):
        {
            u16 total_fat_calories @ p;
        }
        (LapFieldDefinitionType::AvgSpeed):
        {
            u16 avg_speed @ p;
        }
        (LapFieldDefinitionType::MaxSpeed):
        {
            u16 max_speed @ p;
        }
        (LapFieldDefinitionType::AvgHeartRate):
        {
            u8 avg_heart_rate @ p;
        }
        (LapFieldDefinitionType::MaxHeartRate):
        {
            u8 max_heart_rate @ p;
        }
        (LapFieldDefinitionType::AvgCadence):
        {
            u8 avg_cadence @ p;
        }
        (LapFieldDefinitionType::MaxCadence):
        {
            u8 max_cadence @ p;
        }
        (LapFieldDefinitionType::AvgPower):
        {
            u16 avg_power @ p;
        }
        (LapFieldDefinitionType::MaxPower):
        {
            u16 max_power @ p;
        }
        (LapFieldDefinitionType::TotalAscent):
        {
            u16 total_ascent @ p;
        }
        (LapFieldDefinitionType::TotalDescent):
        {
            u16 total_descent @ p;
        }
        (LapFieldDefinitionType::Intensity):
        {
            IntensityType intensity @ p;
        }
        (LapFieldDefinitionType::LapTrigger):
        {
            LapTriggerType lap_trigger @ p;
        }
        (LapFieldDefinitionType::Sport):
        {
            SportType sport @ p;
        }
        (LapFieldDefinitionType::EventGroup):
        {
            u8 event_group @ p;
        }
        (LapFieldDefinitionType::NumLengths):
        {
            u16 num_lengths @ p;
        }
        (LapFieldDefinitionType::NormalizedPower):
        {
            u16 normalized_power @ p;
        }
        (LapFieldDefinitionType::LeftRightBalance):
        {
            LeftRightBalance100Type left_right_balance @ p;
        }
        (LapFieldDefinitionType::FirstLengthIndex):
        {
            u16 first_length_index @ p;
        }
        (LapFieldDefinitionType::AvgStrokeDistance):
        {
            u16 avg_stroke_distance @ p;
        }
        (LapFieldDefinitionType::SwimStroke):
        {
            SwimStrokeType swim_stroke @ p;
        }
        (LapFieldDefinitionType::SubSport):
        {
            SubSportType sub_sport @ p;
        }
        (LapFieldDefinitionType::NumActiveLengths):
        {
            u16 num_active_lengths @ p;
        }
        (LapFieldDefinitionType::TotalWork):
        {
            u32 total_work @ p;
        }
        (LapFieldDefinitionType::AvgAltitude):
        {
            u16 avg_altitude @ p;
        }
        (LapFieldDefinitionType::MaxAltitude):
        {
            u16 max_altitude @ p;
        }
        (LapFieldDefinitionType::GpsAccuracy):
        {
            u8 gps_accuracy @ p;
        }
        (LapFieldDefinitionType::AvgGrade):
        {
            s16 avg_grade @ p;
        }
        (LapFieldDefinitionType::AvgPosGrade):
        {
            s16 avg_pos_grade @ p;
        }
        (LapFieldDefinitionType::AvgNegGrade):
        {
            s16 avg_neg_grade @ p;
        }
        (LapFieldDefinitionType::MaxPosGrade):
        {
            s16 max_pos_grade @ p;
        }
        (LapFieldDefinitionType::MaxNegGrade):
        {
            s16 max_neg_grade @ p;
        }
        (LapFieldDefinitionType::AvgTemperature):
        {
            s8 avg_temperature @ p;
        }
        (LapFieldDefinitionType::MaxTemperature):
        {
            s8 max_temperature @ p;
        }
        (LapFieldDefinitionType::TotalMovingTime):
        {
            u32 total_moving_time @ p;
        }
        (LapFieldDefinitionType::AvgPosVerticalSpeed):
        {
            s16 avg_pos_vertical_speed @ p;
        }
        (LapFieldDefinitionType::AvgNegVerticalSpeed):
        {
            s16 avg_neg_vertical_speed @ p;
        }
        (LapFieldDefinitionType::MaxPosVerticalSpeed):
        {
            s16 max_pos_vertical_speed @ p;
        }
        (LapFieldDefinitionType::MaxNegVerticalSpeed):
        {
            s16 max_neg_vertical_speed @ p;
        }
        (LapFieldDefinitionType::TimeInHrZone):
        {
            u32 time_in_hr_zone @ p;
        }
        (LapFieldDefinitionType::TimeInSpeedZone):
        {
            u32 time_in_speed_zone @ p;
        }
        (LapFieldDefinitionType::TimeInCadenceZone):
        {
            u32 time_in_cadence_zone @ p;
        }
        (LapFieldDefinitionType::TimeInPowerZone):
        {
            u32 time_in_power_zone @ p;
        }
        (LapFieldDefinitionType::RepetitionNum):
        {
            u16 repetition_num @ p;
        }
        (LapFieldDefinitionType::MinAltitude):
        {
            u16 min_altitude @ p;
        }
        (LapFieldDefinitionType::MinHeartRate):
        {
            u8 min_heart_rate @ p;
        }
        (LapFieldDefinitionType::WktStepIndex):
        {
            MessageIndexType wkt_step_index @ p;
        }
        (LapFieldDefinitionType::OpponentScore):
        {
            u16 opponent_score @ p;
        }
        (LapFieldDefinitionType::StrokeCount):
        {
            u16 stroke_count @ p;
        }
        (LapFieldDefinitionType::ZoneCount):
        {
            u16 zone_count @ p;
        }
        (LapFieldDefinitionType::AvgVerticalOscillation):
        {
            u16 avg_vertical_oscillation @ p;
        }
        (LapFieldDefinitionType::AvgStanceTimePercent):
        {
            u16 avg_stance_time_percent @ p;
        }
        (LapFieldDefinitionType::AvgStanceTime):
        {
            u16 avg_stance_time @ p;
        }
        (LapFieldDefinitionType::AvgFractionalCadence):
        {
            u8 avg_fractional_cadence @ p;
        }
        (LapFieldDefinitionType::MaxFractionalCadence):
        {
            u8 max_fractional_cadence @ p;
        }
        (LapFieldDefinitionType::TotalFractionalCycles):
        {
            u8 total_fractional_cycles @ p;
        }
        (LapFieldDefinitionType::PlayerScore):
        {
            u16 player_score @ p;
        }
        (LapFieldDefinitionType::AvgTotalHemoglobinConc):
        {
            u16 avg_total_hemoglobin_conc @ p;
        }
        (LapFieldDefinitionType::MinTotalHemoglobinConc):
        {
            u16 min_total_hemoglobin_conc @ p;
        }
        (LapFieldDefinitionType::MaxTotalHemoglobinConc):
        {
            u16 max_total_hemoglobin_conc @ p;
        }
        (LapFieldDefinitionType::AvgSaturatedHemoglobinPercent):
        {
            u16 avg_saturated_hemoglobin_percent @ p;
        }
        (LapFieldDefinitionType::MinSaturatedHemoglobinPercent):
        {
            u16 min_saturated_hemoglobin_percent @ p;
        }
        (LapFieldDefinitionType::MaxSaturatedHemoglobinPercent):
        {
            u16 max_saturated_hemoglobin_percent @ p;
        }
        (LapFieldDefinitionType::AvgLeftTorqueEffectiveness):
        {
            u8 avg_left_torque_effectiveness @ p;
        }
        (LapFieldDefinitionType::AvgRightTorqueEffectiveness):
        {
            u8 avg_right_torque_effectiveness @ p;
        }
        (LapFieldDefinitionType::AvgLeftPedalSmoothness):
        {
            u8 avg_left_pedal_smoothness @ p;
        }
        (LapFieldDefinitionType::AvgRightPedalSmoothness):
        {
            u8 avg_right_pedal_smoothness @ p;
        }
        (LapFieldDefinitionType::AvgCombinedPedalSmoothness):
        {
            u8 avg_combined_pedal_smoothness @ p;
        }
        (LapFieldDefinitionType::TimeStanding):
        {
            u32 time_standing @ p;
        }
        (LapFieldDefinitionType::StandCount):
        {
            u16 stand_count @ p;
        }
        (LapFieldDefinitionType::AvgLeftPco):
        {
            s8 avg_left_pco @ p;
        }
        (LapFieldDefinitionType::AvgRightPco):
        {
            s8 avg_right_pco @ p;
        }
        (LapFieldDefinitionType::AvgLeftPowerPhase):
        {
            u8 avg_left_power_phase @ p;
        }
        (LapFieldDefinitionType::AvgLeftPowerPhasePeak):
        {
            u8 avg_left_power_phase_peak @ p;
        }
        (LapFieldDefinitionType::AvgRightPowerPhase):
        {
            u8 avg_right_power_phase @ p;
        }
        (LapFieldDefinitionType::AvgRightPowerPhasePeak):
        {
            u8 avg_right_power_phase_peak @ p;
        }
        (LapFieldDefinitionType::AvgPowerPosition):
        {
            u16 avg_power_position @ p;
        }
        (LapFieldDefinitionType::MaxPowerPosition):
        {
            u16 max_power_position @ p;
        }
        (LapFieldDefinitionType::AvgCadencePosition):
        {
            u8 avg_cadence_position @ p;
        }
        (LapFieldDefinitionType::MaxCadencePosition):
        {
            u8 max_cadence_position @ p;
        }
        (LapFieldDefinitionType::EnhancedAvgSpeed):
        {
            u32 enhanced_avg_speed @ p;
        }
        (LapFieldDefinitionType::EnhancedMaxSpeed):
        {
            u32 enhanced_max_speed @ p;
        }
        (LapFieldDefinitionType::EnhancedAvgAltitude):
        {
            u32 enhanced_avg_altitude @ p;
        }
        (LapFieldDefinitionType::EnhancedMinAltitude):
        {
            u32 enhanced_min_altitude @ p;
        }
        (LapFieldDefinitionType::EnhancedMaxAltitude):
        {
            u32 enhanced_max_altitude @ p;
        }
        (LapFieldDefinitionType::AvgLevMotorPower):
        {
            u16 avg_lev_motor_power @ p;
        }
        (LapFieldDefinitionType::MaxLevMotorPower):
        {
            u16 max_lev_motor_power @ p;
        }
        (LapFieldDefinitionType::LevBatteryConsumption):
        {
            u8 lev_battery_consumption @ p;
        }
        (LapFieldDefinitionType::AvgVerticalRatio):
        {
            u16 avg_vertical_ratio @ p;
        }
        (LapFieldDefinitionType::AvgStanceTimeBalance):
        {
            u16 avg_stance_time_balance @ p;
        }
        (LapFieldDefinitionType::AvgStepLength):
        {
            u16 avg_step_length @ p;
        }
        (LapFieldDefinitionType::AvgVam):
        {
            u16 avg_vam @ p;
        }
        (LapFieldDefinitionType::AvgDepth):
        {
            u32 avg_depth @ p;
        }
        (LapFieldDefinitionType::MaxDepth):
        {
            u32 max_depth @ p;
        }
        (LapFieldDefinitionType::MinTemperature):
        {
            s8 min_temperature @ p;
        }
        (LapFieldDefinitionType::EnhancedAvgRespirationRate):
        {
            u16 enhanced_avg_respiration_rate @ p;
        }
        (LapFieldDefinitionType::EnhancedMaxRespirationRate):
        {
            u16 enhanced_max_respiration_rate @ p;
        }
        (LapFieldDefinitionType::AvgRespirationRate):
        {
            u8 avg_respiration_rate @ p;
        }
        (LapFieldDefinitionType::MaxRespirationRate):
        {
            u8 max_respiration_rate @ p;
        }
        (LapFieldDefinitionType::TotalGrit):
        {
            float total_grit @ p;
        }
        (LapFieldDefinitionType::TotalFlow):
        {
            float total_flow @ p;
        }
        (LapFieldDefinitionType::JumpCount):
        {
            u16 jump_count @ p;
        }
        (LapFieldDefinitionType::AvgGrit):
        {
            float avg_grit @ p;
        }
        (LapFieldDefinitionType::AvgFlow):
        {
            float avg_flow @ p;
        }
        (LapFieldDefinitionType::TotalFractionalAscent):
        {
            u8 total_fractional_ascent @ p;
        }
        (LapFieldDefinitionType::TotalFractionalDescent):
        {
            u8 total_fractional_descent @ p;
        }
        (LapFieldDefinitionType::AvgCoreTemperature):
        {
            u16 avg_core_temperature @ p;
        }
        (LapFieldDefinitionType::MinCoreTemperature):
        {
            u16 min_core_temperature @ p;
        }
        (LapFieldDefinitionType::MaxCoreTemperature):
        {
            u16 max_core_temperature @ p;
        }
        (LapFieldDefinitionType::Timestamp):
        {
            DateTime timestamp @ p[[format("format_datetime")]];
        }
        (LapFieldDefinitionType::MessageIndex):
        {
            MessageIndexType message_index @ p;
        }
    }
    $ += s;
};

fn format_distance(u32 dist) 
{
    u32 scaled = dist / 100;
    float km = float(scaled) / 1000.0;
    u32 trunc_km_int = u32(std::math::trunc(1000.0 * km));
    float trunc_km = float(trunc_km_int) / 1000.0f;
    return std::format("{:.2}km ({}m)", trunc_km, scaled);
};

struct RecordField
{
    auto i = std::core::array_index();
    auto s = scratch_defs[i].size;
    auto p = $;
    match (scratch_defs[i].field_definition_num) 
    {
        (RecordFieldDefinitionType::PositionLat):
        {
            s32 position_lat @ p;
        }
        (RecordFieldDefinitionType::PositionLong):
        {
            s32 position_long @ p;
        }
        (RecordFieldDefinitionType::Altitude):
        {
            u16 altitude @ p;
        }
        (RecordFieldDefinitionType::HeartRate):
        {
            u8 heart_rate @ p;
        }
        (RecordFieldDefinitionType::Cadence):
        {
            u8 cadence @ p;
        }
        (RecordFieldDefinitionType::Distance):
        {
            u32 distance @ p [[format("format_distance")]];
        }
        (RecordFieldDefinitionType::Speed):
        {
            u16 speed @ p;
        }
        (RecordFieldDefinitionType::Power):
        {
            u16 power @ p;
        }
        (RecordFieldDefinitionType::CompressedSpeedDistance):
        {
            CompressedSpeedDistanceBitField compressed_speed_distance @ p [[bitfield_order(std::core::BitfieldOrder::MostToLeastSignificant, 12)]];;
        }
        (RecordFieldDefinitionType::Grade):
        {
            s16 grade @ p;
        }
        (RecordFieldDefinitionType::Resistance):
        {
            u8 resistance @ p;
        }
        (RecordFieldDefinitionType::TimeFromCourse):
        {
            s32 time_from_course @ p;
        }
        (RecordFieldDefinitionType::CycleLength):
        {
            u8 cycle_length @ p;
        }
        (RecordFieldDefinitionType::Temperature):
        {
            s8 temperature @ p;
        }
        (RecordFieldDefinitionType::Speed1s):
        {
            u8 speed_1s @ p;
        }
        (RecordFieldDefinitionType::Cycles):
        {
            u8 cycles @ p;
        }
        (RecordFieldDefinitionType::TotalCycles):
        {
            u32 total_cycles @ p;
        }
        (RecordFieldDefinitionType::CompressedAccumulatedPower):
        {
            u16 compressed_accumulated_power @ p;
        }
        (RecordFieldDefinitionType::AccumulatedPower):
        {
            u32 accumulated_power @ p;
        }
        (RecordFieldDefinitionType::LeftRightBalance):
        {
            LeftRightBalanceType left_right_balance @ p;
        }
        (RecordFieldDefinitionType::GpsAccuracy):
        {
            u8 gps_accuracy @ p;
        }
        (RecordFieldDefinitionType::VerticalSpeed):
        {
            s16 vertical_speed @ p;
        }
        (RecordFieldDefinitionType::Calories):
        {
            u16 calories @ p;
        }
        (RecordFieldDefinitionType::VerticalOscillation):
        {
            u16 vertical_oscillation @ p;
        }
        (RecordFieldDefinitionType::StanceTimePercent):
        {
            u16 stance_time_percent @ p;
        }
        (RecordFieldDefinitionType::StanceTime):
        {
            u16 stance_time @ p;
        }
        (RecordFieldDefinitionType::ActivityType):
        {
            ActivityType activity_type @ p;
        }
        (RecordFieldDefinitionType::LeftTorqueEffectiveness):
        {
            u8 left_torque_effectiveness @ p;
        }
        (RecordFieldDefinitionType::RightTorqueEffectiveness):
        {
            u8 right_torque_effectiveness @ p;
        }
        (RecordFieldDefinitionType::LeftPedalSmoothness):
        {
            u8 left_pedal_smoothness @ p;
        }
        (RecordFieldDefinitionType::RightPedalSmoothness):
        {
            u8 right_pedal_smoothness @ p;
        }
        (RecordFieldDefinitionType::CombinedPedalSmoothness):
        {
            u8 combined_pedal_smoothness @ p;
        }
        (RecordFieldDefinitionType::Time128):
        {
            u8 time128 @ p;
        }
        (RecordFieldDefinitionType::StrokeType):
        {
            StrokeType stroke_type @ p;
        }
        (RecordFieldDefinitionType::Zone):
        {
            u8 zone @ p;
        }
        (RecordFieldDefinitionType::BallSpeed):
        {
            u16 ball_speed @ p;
        }
        (RecordFieldDefinitionType::Cadence256):
        {
            u16 cadence256 @ p;
        }
        (RecordFieldDefinitionType::FractionalCadence):
        {
            u8 fractional_cadence @ p;
        }
        (RecordFieldDefinitionType::TotalHemoglobinConc):
        {
            u16 total_hemoglobin_conc @ p;
        }
        (RecordFieldDefinitionType::TotalHemoglobinConcMin):
        {
            u16 total_hemoglobin_conc_min @ p;
        }
        (RecordFieldDefinitionType::TotalHemoglobinConcMax):
        {
            u16 total_hemoglobin_conc_max @ p;
        }
        (RecordFieldDefinitionType::SaturatedHemoglobinPercent):
        {
            u16 saturated_hemoglobin_percent @ p;
        }
        (RecordFieldDefinitionType::SaturatedHemoglobinPercentMin):
        {
            u16 saturated_hemoglobin_percent_min @ p;
        }
        (RecordFieldDefinitionType::SaturatedHemoglobinPercentMax):
        {
            u16 saturated_hemoglobin_percent_max @ p;
        }
        (RecordFieldDefinitionType::DeviceIndex):
        {
            DeviceIndexType device_index @ p;
        }
        (RecordFieldDefinitionType::LeftPco):
        {
            s8 left_pco @ p;
        }
        (RecordFieldDefinitionType::RightPco):
        {
            s8 right_pco @ p;
        }
        (RecordFieldDefinitionType::LeftPowerPhase):
        {
            u8 left_power_phase @ p;
        }
        (RecordFieldDefinitionType::LeftPowerPhasePeak):
        {
            u8 left_power_phase_peak @ p;
        }
        (RecordFieldDefinitionType::RightPowerPhase):
        {
            u8 right_power_phase @ p;
        }
        (RecordFieldDefinitionType::RightPowerPhasePeak):
        {
            u8 right_power_phase_peak @ p;
        }
        (RecordFieldDefinitionType::EnhancedSpeed):
        {
            u32 enhanced_speed @ p;
        }
        (RecordFieldDefinitionType::EnhancedAltitude):
        {
            u32 enhanced_altitude @ p;
        }
        (RecordFieldDefinitionType::BatterySoc):
        {
            u8 battery_soc @ p;
        }
        (RecordFieldDefinitionType::MotorPower):
        {
            u16 motor_power @ p;
        }
        (RecordFieldDefinitionType::VerticalRatio):
        {
            u16 vertical_ratio @ p;
        }
        (RecordFieldDefinitionType::StanceTimeBalance):
        {
            u16 stance_time_balance @ p;
        }
        (RecordFieldDefinitionType::StepLength):
        {
            u16 step_length @ p;
        }
        (RecordFieldDefinitionType::CycleLength16):
        {
            u16 cycle_length16 @ p;
        }
        (RecordFieldDefinitionType::AbsolutePressure):
        {
            u32 absolute_pressure @ p;
        }
        (RecordFieldDefinitionType::Depth):
        {
            u32 depth @ p;
        }
        (RecordFieldDefinitionType::NextStopDepth):
        {
            u32 next_stop_depth @ p;
        }
        (RecordFieldDefinitionType::NextStopTime):
        {
            u32 next_stop_time @ p;
        }
        (RecordFieldDefinitionType::TimeToSurface):
        {
            u32 time_to_surface @ p;
        }
        (RecordFieldDefinitionType::NdlTime):
        {
            u32 ndl_time @ p;
        }
        (RecordFieldDefinitionType::CnsLoad):
        {
            u8 cns_load @ p;
        }
        (RecordFieldDefinitionType::N2Load):
        {
            u16 N2_load @ p;
        }
        (RecordFieldDefinitionType::RespirationRate):
        {
            u8 respiration_rate @ p;
        }
        (RecordFieldDefinitionType::EnhancedRespirationRate):
        {
            u16 enhanced_respiration_rate @ p;
        }
        (RecordFieldDefinitionType::Grit):
        {
            float grit @ p;
        }
        (RecordFieldDefinitionType::Flow):
        {
            float flow @ p;
        }
        (RecordFieldDefinitionType::CurrentStress):
        {
            u16 current_stress @ p;
        }
        (RecordFieldDefinitionType::EbikeTravelRange):
        {
            u16 ebike_travel_range @ p;
        }
        (RecordFieldDefinitionType::EbikeBatteryLevel):
        {
            u8 ebike_battery_level @ p;
        }
        (RecordFieldDefinitionType::EbikeAssistMode):
        {
            u8 ebike_assist_mode @ p;
        }
        (RecordFieldDefinitionType::EbikeAssistLevelPercent):
        {
            u8 ebike_assist_level_percent @ p;
        }
        (RecordFieldDefinitionType::AirTimeRemaining):
        {
            u32 air_time_remaining @ p;
        }
        (RecordFieldDefinitionType::PressureSac):
        {
            u16 pressure_sac @ p;
        }
        (RecordFieldDefinitionType::VolumeSac):
        {
            u16 volume_sac @ p;
        }
        (RecordFieldDefinitionType::Rmv):
        {
            u16 rmv @ p;
        }
        (RecordFieldDefinitionType::AscentRate):
        {
            s32 ascent_rate @ p;
        }
        (RecordFieldDefinitionType::Po2):
        {
            u8 po2 @ p;
        }
        (RecordFieldDefinitionType::CoreTemperature):
        {
            u16 core_temperature @ p;
        }
        (RecordFieldDefinitionType::Timestamp):
        {
            DateTime timestamp @ p[[format("format_datetime")]];
        }
    }
    $ += s;
};

struct FileIdField 
{
    auto i = std::core::array_index();
    auto s = scratch_defs[i].size;
    auto p = $;
    u8 fdn = u8(scratch_defs[i].field_definition_num);
    //std::print(std::format("FieldIdField: Index:{},Size:{},Pointer:{} FDN: {}", i, s, p, fdn));
    match (fdn) 
    {
        (FileIdFieldDefinitionType::TimeCreated): {
            if(scratch_fix_header.architecture == Architecture::BigEndian){
                be DateTime time_created @ p [[format("format_local_datetime")]];
            }
            else
            {
                le DateTime time_created @ p [[format("format_local_datetime")]];
            }
            scratch_time_created = time_created;
        }
        (FileIdFieldDefinitionType::Type): {
            FileType type @ p;
        }
        (FileIdFieldDefinitionType::Manufacturer):
        {
            u16 manufacturer @ p;
        }
        (FileIdFieldDefinitionType::Product): 
        {
            u16 product @ p;
        }
        (FileIdFieldDefinitionType::SerialNumber): 
        {
            u32 serial_number @ p;
        }
        (FileIdFieldDefinitionType::Number): 
        {
            u16 number @ p;
        }
        (FileIdFieldDefinitionType::ProductName): 
        {
            str product_name @ p;
        }
    }
    $ += s;
};

struct DataMessage
{
    MsgNum subtype = scratch_fix_header.global_msg_num;
#ifdef DEBUG_MODE
    try
    {
#endif
        match(subtype)
        {
            (MsgNum::FileId): FileIdField fields[scratch_fix_header.field_num];
            (MsgNum::Activity): ActivityField fields[scratch_fix_header.field_num];
            (MsgNum::Session): SessionField fields[scratch_fix_header.field_num];
            (MsgNum::Lap): LapField fields[scratch_fix_header.field_num];
            (MsgNum::Record): RecordField fields[scratch_fix_header.field_num];
            (_): std::error(std::format("Invalid data message type code! MsgNum:{}", u16(subtype)));
        }
#ifdef DEBUG_MODE
    }
    catch{
        break;
    }
#endif
};

struct Record
{
    RecordHeader rec_header;  
    if( rec_header.normal_header == 0 
        && rec_header.message_type == 1)
    {
        DefinitionMessage message;
    }
    else
    {
        DataMessage message;
    }

} [[format("record_formatter")]];

fn record_formatter(Record r)
{
    str msg = "";
    if(r.rec_header.message_type == 1){
        msg = "Definition Msg";
        msg += "-";
        msg += std::string::to_string(r.message.fix_header.global_msg_num);
    }
    else
    {
        msg = "Data Msg";
        msg += "-";
        MsgNum mn = r.message.subtype;
        msg += std::string::to_string(mn);
    }
    
    return msg;
};

struct FitFile
{
    Header header;
#ifdef DEBUG_MODE
    Record records[10] @ sizeof(Header);
#endif
#ifndef DEBUG_MODE
    Record records[while(!std::mem::reached(sizeof(Header) + header.data_size))] @ sizeof(Header);
#endif
    le u16 CRC @ sizeof(Header) + header.data_size;
};

clearScratchFixedHeader();
clearScratchDefinitions();
std::print("Decoding..");
FitFile fit @0x00 [[pointer_base]];


fn ValidateFile(u8 header_size, u32 data_size)
{
    u32 size = header_size + data_size + 2;
    
    std::mem::Section crc_scratch = std::mem::create_section("CRCScratch");
    std::mem::set_section_size(crc_scratch, size);
    u8 data[size] @ 0x00 in crc_scratch;
    std::mem::copy_section_to_section(0, 0x00, crc_scratch, 0x00, size);
    
    u16 crc = 0;
    crc = check_crc(crc, data, size);
    std::mem::delete_section(crc_scratch);
    
    if(crc == 0)
    {
        std::print("File CRC is valid");
    }
    else
    {
        std::print("File CRC is not valid");
    }
};

ValidateFile(fit.header.header_size, fit.header.data_size);
std::mem::delete_section(scratch);
std::print("Done");