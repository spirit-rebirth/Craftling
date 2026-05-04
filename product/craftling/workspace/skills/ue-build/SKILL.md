---
name: ue-build
description: "Build Unreal Engine C++ changes for the active project with UnrealBuildTool / Build.bat, diagnose build failures, and guide the agent through compile-repair steps."
---
# UE Code Generation Skill

## Overview

You are a code generation agent for Unreal Engine 5.6+ C++ projects. You generate production-quality UE C++ classes that follow engine conventions and compile cleanly on the first attempt.

## Project Context

- **Module name:** configured per project; infer from the active Unreal project or local OpenClaw config.
- **Source directory:** the active Unreal project source module directory.
- **Build system:** UnrealBuildTool (UBT)
- **Target:** Win64 Development Editor

## File Conventions

### Naming Rules

| Type | Prefix | Example |
|------|--------|---------|
| Actor | `A` | `AHealthPickup` |
| UObject / Component | `U` | `UInventoryComponent` |
| Struct | `F` | `FPickupData` |
| Interface | `I` (interface) / `U` (UObject) | `IInteractable` / `UInteractableInterface` |
| Enum | `E` | `EPickupType` |
| Template | `T` | `TInventoryIterator` |

### File Naming

- One class per file pair
- Filename matches class name **without** the prefix: `AHealthPickup` 閳?`HealthPickup.h` / `HealthPickup.cpp`
- All files go in the active Unreal project source module directory.

### Header File Structure (.h)

```cpp
// <copyright or project header 閳?optional for MVP>

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"  // Base class header
// Other includes as needed
#include "ClassName.generated.h"  // MUST be last include

UCLASS()
class PROJECTMODULE_API AClassName : public AActor
{
    GENERATED_BODY()

public:
    AClassName();

protected:
    virtual void BeginPlay() override;

public:
    virtual void Tick(float DeltaTime) override;

    // -- Properties --

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "MyCategory")
    float MyProperty = 100.0f;

    // -- Components --

    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components")
    UStaticMeshComponent* MeshComp;

    // -- Functions --

    UFUNCTION(BlueprintCallable, Category = "MyCategory")
    void MyFunction();
};
```

### Source File Structure (.cpp)

```cpp
#include "ClassName.h"  // OWN header MUST be first include

// Additional includes
#include "Components/SphereComponent.h"
#include "Kismet/GameplayStatics.h"

AClassName::AClassName()
{
    PrimaryActorTick.bCanEverTick = false;  // Default to false unless needed

    // Create components in constructor
    MeshComp = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComp"));
    RootComponent = MeshComp;
}

void AClassName::BeginPlay()
{
    Super::BeginPlay();
}

void AClassName::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);
}

void AClassName::MyFunction()
{
    // Implementation
}
```

## UCLASS / UPROPERTY / UFUNCTION Reference

### UCLASS Specifiers (most common)

- `Blueprintable` 閳?Can be subclassed in Blueprints
- `BlueprintType` 閳?Can be used as a variable type in Blueprints
- `Abstract` 閳?Cannot be instantiated
- `NotBlueprintable` 閳?Cannot be subclassed
- `ClassGroup=GroupName` 閳?Editor organization
- `meta=(BlueprintSpawnableComponent)` 閳?For components placeable via Blueprint editor

### UPROPERTY Specifiers

**Access:**
- `EditAnywhere` 閳?Editable on class defaults and instances
- `EditDefaultsOnly` 閳?Editable only on class defaults (CDO)
- `EditInstanceOnly` 閳?Editable only on placed instances
- `VisibleAnywhere` 閳?Read-only in editor (good for components)
- `BlueprintReadWrite` 閳?Read+write from Blueprints
- `BlueprintReadOnly` 閳?Read-only from Blueprints

**Behavior:**
- `Replicated` 閳?Replicated over network
- `Transient` 閳?Not saved to disk
- `Category = "Name"` 閳?Groups in editor details panel

**Common combos:**
- Tunable gameplay value: `UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gameplay")`
- Component reference: `UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components")`
- Internal state: `UPROPERTY(BlueprintReadOnly, Category = "State")`

### UFUNCTION Specifiers

- `BlueprintCallable` 閳?Can call from Blueprint graphs
- `BlueprintPure` 閳?No side effects, no exec pin
- `BlueprintImplementableEvent` 閳?Defined in Blueprint, no C++ body
- `BlueprintNativeEvent` 閳?C++ default, overridable in Blueprint (needs `_Implementation`)
- `Server` / `Client` / `NetMulticast` 閳?Network RPCs
- `Reliable` / `Unreliable` 閳?Network reliability

## Module Dependencies

When your generated code uses types from other modules, you must add them to `<ProjectModule>.Build.cs`.

Open `Source/<ProjectModule>/<ProjectModule>.Build.cs` and add to `PublicDependencyModuleNames`:

```csharp
PublicDependencyModuleNames.AddRange(new string[] {
    "Core",
    "CoreUObject",
    "Engine",
    "InputCore",
    // Add new modules here as needed:
    // "UMG"           閳?for UI widgets
    // "AIModule"      閳?for AI/behavior trees
    // "NavigationSystem" 閳?for navmesh queries
    // "GameplayTasks" 閳?for gameplay abilities
    // "PhysicsCore"   閳?for physics queries
    // "EnhancedInput" 閳?for Enhanced Input System
});
```

**Rule:** Before generating code that uses types from a non-default module, check `Build.cs` and add the dependency if missing.

## Common Include Paths

```cpp
// Components
#include "Components/SphereComponent.h"
#include "Components/BoxComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/AudioComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/ArrowComponent.h"
#include "Components/WidgetComponent.h"

// Gameplay
#include "GameFramework/Actor.h"
#include "GameFramework/Character.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/CharacterMovementComponent.h"

// Utilities
#include "Kismet/GameplayStatics.h"
#include "Kismet/KismetMathLibrary.h"
#include "TimerManager.h"
#include "Engine/World.h"
#include "DrawDebugHelpers.h"

// Collision
#include "CollisionQueryParams.h"
#include "Engine/EngineTypes.h"

// Logging
#include "Logging/LogMacros.h"
```

## Logging Convention

Use UE's structured logging, not `printf` or `std::cout`:

```cpp
// Declare a log category (in .h or a shared header)
DECLARE_LOG_CATEGORY_EXTERN(LogAgentTest, Log, All);

// Define it (in .cpp)
DEFINE_LOG_CATEGORY(LogAgentTest);

// Usage
UE_LOG(LogAgentTest, Log, TEXT("Pickup collected by %s"), *OtherActor->GetName());
UE_LOG(LogAgentTest, Warning, TEXT("Health amount is zero!"));
UE_LOG(LogAgentTest, Error, TEXT("Failed to find component on %s"), *GetName());
```

For the MVP, using `LogTemp` is acceptable:

```cpp
UE_LOG(LogTemp, Log, TEXT("HealthPickup: Collected by %s, restored %f HP"), *OtherActor->GetName(), HealthAmount);
```

**Prefix log messages with `[AgentTest]` so the observation system can filter them:**

```cpp
UE_LOG(LogTemp, Log, TEXT("[AgentTest] PICKUP_COLLECTED: %s, Health: %f -> %f"),
    *GetName(), OldHealth, NewHealth);
```

## Overlap / Collision Patterns

### Overlap Detection (most common for pickups, triggers, zones)

```cpp
// In header 閳?declare the component and callback
UPROPERTY(VisibleAnywhere)
USphereComponent* CollisionComp;

UFUNCTION()
void OnOverlapBegin(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
    UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
    bool bFromSweep, const FHitResult& SweepResult);

// In constructor 閳?create and configure
CollisionComp = CreateDefaultSubobject<USphereComponent>(TEXT("CollisionComp"));
CollisionComp->SetSphereRadius(100.0f);
CollisionComp->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
CollisionComp->SetGenerateOverlapEvents(true);
RootComponent = CollisionComp;

// In BeginPlay 閳?bind the delegate
CollisionComp->OnComponentBeginOverlap.AddDynamic(this, &AMyActor::OnOverlapBegin);
```

### Alternative: Override NotifyActorBeginOverlap

Simpler for cases where you don't need component-level granularity:

```cpp
// In header
virtual void NotifyActorBeginOverlap(AActor* OtherActor) override;

// In cpp
void AMyActor::NotifyActorBeginOverlap(AActor* OtherActor)
{
    Super::NotifyActorBeginOverlap(OtherActor);
    // Your logic here
}
```

**Note:** The actor's root component must still generate overlap events for this to fire.

## Timer Pattern

```cpp
// In header
FTimerHandle DamageTimerHandle;

void ApplyDamage();

// Start timer
GetWorldTimerManager().SetTimer(DamageTimerHandle, this, &AMyActor::ApplyDamage, 1.0f, true);

// Stop timer
GetWorldTimerManager().ClearTimer(DamageTimerHandle);
```

## Generation Checklist

Before finishing code generation, verify:

1. [ ] Header uses `#pragma once`
2. [ ] `.generated.h` is the last include in the header
3. [ ] `GENERATED_BODY()` is first line inside the class
4. [ ] Own header is first include in the `.cpp`
5. [ ] API macro is present: `PROJECTMODULE_API`
6. [ ] All UPROPERTY/UFUNCTION macros have correct specifiers
7. [ ] Components created with `CreateDefaultSubobject` in constructor (not BeginPlay)
8. [ ] Overlap/collision components call `SetGenerateOverlapEvents(true)`
9. [ ] Delegate bindings use `AddDynamic` in BeginPlay (not constructor)
10. [ ] Super:: calls present in all overridden functions
11. [ ] No `#include` cycles (forward-declare where possible)
12. [ ] Module dependencies in Build.cs are satisfied

## Templates

Reference templates are available in the `templates/` directory alongside this file. Use them as starting points and customize for the specific task.
